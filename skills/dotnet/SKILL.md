---
name: dotnet
description: Use when writing or changing a C# ASP.NET Core app on .NET 10 — the solution layout, Directory.Build.props, central package management and lock files, nullable and warnings as errors, configuration from appsettings.json and environment variables with the options pattern, health endpoints, logging, EF Core migrations run by the pipeline, xUnit tests with WebApplicationFactory, and one publish that runs on IIS with Web Deploy, as a systemd service behind nginx, or in a Docker image (e.g. "start a new .NET 10 web API", "add a config section with validation", "add a health check", "add an EF Core migration", "write an integration test for this endpoint", "publish this API for IIS and Linux", "why does the app read the wrong settings in production"). For the pipeline that builds and deploys it, use gitlab-ci; for reviewing .NET code, use dotnet-review.
---

# .NET

Write the app so one build runs in every environment and on every host kind. The pipeline
builds it once, tests it, and deploys that same folder or image to staging and then prod
(`gitlab-ci`, section 4). So nothing that differs between environments may be in the
build: no environment-specific appsettings file, no connection string, no secret. Most
.NET trouble in production is one of these: settings baked into the artifact, a migration
that ran at startup, a call that blocks a thread, or a build that worked only on one
machine.

The pipeline is `gitlab-ci`; the hosts (IIS, nginx, the systemd unit, Docker) are
prepared by `ansible`; the compose file and the image's way through the registry are
`docker`. For the database schema, `schema-design`; for SQL inside the app,
`sql-writing`. For a review of finished code, the `dotnet-review` skill, or the
`dotnet-reviewer` agent for a check that runs unattended. For comments, `code-comments`.
The worked example is
`evals/examples/dotnet/` in the skills repo: `Orders.Api` with a test project and the
Dockerfile, the app that `evals/examples/gitlab-ci/app/` deploys.

## 0. Check what is there

- `dotnet --info`: the SDK and runtimes on this machine. The CI image is
  `mcr.microsoft.com/dotnet/sdk:10.0.404`; `global.json` pins the same SDK so a local
  build and the pipeline agree.
- **The runtime on each host kind.** IIS needs the ASP.NET Core Hosting Bundle 10.0,
  Linux the ASP.NET Core runtime 10.0, Docker the `aspnet:10.0.x` image. A
  framework-dependent app runs on the newest 10.0 patch installed, so patch the hosts and
  the image together.
- An existing solution: `.sln` or `.slnx`, `Directory.Build.props`, and whether package
  versions are already central.

## 1. Layout and build settings

```
Orders.slnx                  the one solution; dotnet test at the root finds it
global.json
Directory.Build.props        settings for every project
Directory.Packages.props     every package version, in one place
src/Orders.Api/              the app
tests/Orders.Api.Tests/      its tests
Dockerfile                   for the Docker deploy path
.dockerignore
```

- **One solution file at the root.** The CI test job runs `dotnet test` with no path, which
  fails when the root has none or two. `dotnet new sln` writes `.slnx` in .NET 10.
- One project per app in `src/`, one test project per app in `tests/`. A class library
  only when two apps share the code, not for layers inside one app.

```json
// global.json
{
  "sdk": {
    "version": "10.0.404",
    "rollForward": "latestPatch"
  }
}
```

```xml
<!-- Directory.Build.props -->
<Project>
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <!-- A vulnerable package fails the build when the advisory is high or critical. -->
    <WarningsNotAsErrors>NU1901;NU1902</WarningsNotAsErrors>
    <AnalysisLevel>latest</AnalysisLevel>
    <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
    <VersionPrefix>1.0.0</VersionPrefix>
    <!-- GitLab sets CI_COMMIT_SHA. It ends up in the informational version: 1.0.0+<sha>. -->
    <SourceRevisionId Condition="'$(CI_COMMIT_SHA)' != ''">$(CI_COMMIT_SHA)</SourceRevisionId>
  </PropertyGroup>
</Project>
```

```xml
<!-- Directory.Packages.props -->
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>
  <ItemGroup>
    <PackageVersion Include="Microsoft.Extensions.Hosting.Systemd" Version="10.0.15" />
    <PackageVersion Include="Microsoft.AspNetCore.Mvc.Testing" Version="10.0.15" />
    <!-- … one line per package; a project's PackageReference has no Version. -->
  </ItemGroup>
</Project>
```

- **Warnings are errors** everywhere, not only in CI, so a warning cannot pile up locally
  and then break the pipeline. NuGet audit warnings count too: a new advisory for a
  package fails the next build of a commit that changed nothing. That is the point; fix
  it by updating the package in `Directory.Packages.props`.
- `AnalysisLevel` `latest` turns on the analyzer rules that find bugs. `latest-recommended`
  adds naming and style rules that fight test names and minimal APIs. Raise single rules
  in `.editorconfig` instead (`dotnet_diagnostic.CA2016.severity = warning`).
- **Lock files.** `RestorePackagesWithLockFile` writes `packages.lock.json` next to each
  project. Commit them. CI restores with `-p:RestoreLockedMode=true` and fails when a
  lock file no longer matches, instead of quietly resolving newer versions. After a
  version change, restore once locally and commit the new lock file with it.
- **The version.** `VersionPrefix` is the human version; the commit sha comes from the
  pipeline. The SDK reads it from `.git` when there is one; the Docker build has no
  `.git`, so it gets `CI_COMMIT_SHA` as a build argument (section 7). Never a version
  file that someone must edit.

## 2. Configuration

One artifact serves staging and prod, so it reads everything that differs at start:
`appsettings.json` for defaults that are the same everywhere, then environment variables
on the host, which override it.

```json
// appsettings.json: the same in every environment, nothing secret
{
  "Logging": { "LogLevel": { "Default": "Information", "Microsoft.AspNetCore": "Warning" } },
  "AllowedHosts": "*",
  "Orders": { "PageSize": 50 }
}
```

```csharp
// OrdersOptions.cs
public sealed class OrdersOptions
{
    public const string Section = "Orders";

    // Differs per environment, so it comes from the host: Orders__PaymentsUrl.
    [Required, Url]
    public string PaymentsUrl { get; init; } = "";

    [Range(1, 500)]
    public int PageSize { get; init; } = 50;
}

// Program.cs
builder.Services.AddOptions<OrdersOptions>()
    .BindConfiguration(OrdersOptions.Section)
    .ValidateDataAnnotations()
    .ValidateOnStart();
```

- **No `appsettings.Staging.json` or `appsettings.Production.json`** with environment
  values. They are in the artifact, so the artifact is no longer the same everywhere,
  and a value fixed for prod needs a new build. `appsettings.Development.json` for local
  values that are not secret is fine.
- **No secret in any appsettings file**, Development included, and no connection string in
  code. Locally, `dotnet user-secrets` (it needs a `UserSecretsId` in the project). On the
  hosts, environment variables.
- **Environment variable names:** `__` for each level. `Orders:PaymentsUrl` is
  `Orders__PaymentsUrl`; `ConnectionStrings:Orders` (read with
  `GetConnectionString("Orders")`) is `ConnectionStrings__Orders`. Variables starting with
  `ASPNETCORE_` or `DOTNET_` are host settings (`ASPNETCORE_URLS`,
  `ASPNETCORE_ENVIRONMENT`), not app settings.
- **`ValidateOnStart`.** A missing or wrong value stops the app at start, so the deploy's
  health check fails and the job is red. Without it, the first request that reads the
  option fails, long after the deploy passed.
- **Inject `IOptions<T>`,** never `IConfiguration`, into the code that uses a value, so the
  section's shape and its checks live in one class.
- **Leave `ASPNETCORE_ENVIRONMENT` unset on staging and prod.** It defaults to
  `Production`, so staging behaves like prod. `Development` only on developer machines,
  through `Properties/launchSettings.json`.
- **Where the hosts keep the variables.** IIS: on the site's application pool (IIS 10 keeps
  them in `applicationHost.config`, outside the site folder), never in the published
  `web.config`, which every deploy overwrites. Linux: the unit's `EnvironmentFile`, a
  root-only file. Docker: the compose `env_file`. Ansible writes all three.
- **Data Protection.** If the app uses cookies, antiforgery, or `IDataProtector`, persist
  its keys where every host reads them (a share or the database) and call
  `SetApplicationName`. Otherwise every restart, and every second host, logs users out.
  An API with bearer tokens only does not need it.

## 3. Program.cs: health, errors, logging

```csharp
using System.Reflection;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.AspNetCore.HttpOverrides;
using Orders.Api;

var builder = WebApplication.CreateBuilder(args);

// Under systemd: tells systemd when the app is ready, and writes logs the journal reads.
// Elsewhere it does nothing.
builder.Services.AddSystemd();

builder.Services.AddOptions<OrdersOptions>()
    .BindConfiguration(OrdersOptions.Section)
    .ValidateDataAnnotations()
    .ValidateOnStart();

builder.Services.AddProblemDetails();
builder.Services.AddHealthChecks();
builder.Services.Configure<ForwardedHeadersOptions>(options =>
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto);

var app = builder.Build();

app.UseForwardedHeaders();
app.UseExceptionHandler();
app.UseStatusCodePages();

app.MapHealthChecks("/health");

app.MapGet("/orders/{id:int}", Results<Ok<Order>, NotFound> (int id) =>
    id == 1 ? TypedResults.Ok(new Order(1, "First order")) : TypedResults.NotFound());

app.Logger.LogInformation("Starting {Version}",
    typeof(Program).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion);

app.Run();
```

- **`GET /health` answers 200 when the app can serve.** Every deploy job checks it
  (`gitlab-ci`, section 4). Add a check for each thing a request cannot do without, such
  as the database (`AddDbContextCheck<OrdersDb>()` from
  `Microsoft.Extensions.Diagnostics.HealthChecks.EntityFrameworkCore`). Not for an outside
  service the app can work without: when it is down, every host would report unhealthy
  at once. The endpoint needs no login, and the default response says only `Healthy` or
  `Unhealthy`; keep it that way.
- **Errors.** `AddProblemDetails` with `UseExceptionHandler` answers an unhandled exception
  with a plain 500 problem response. The exception goes to the log, never to the client.
  The developer exception page turns on by itself in `Development` only.
- **Forwarded headers.** Behind nginx, `UseForwardedHeaders` makes the app see `https` and
  the client's address. The defaults trust only a proxy on loopback, which is the
  Linux setup. In Docker the proxy is on another address: add its network to
  `KnownIPNetworks`. On IIS the ASP.NET Core Module does this; the call does no harm.
- **Logging** through `ILogger` with message templates:
  `logger.LogInformation("Order {OrderId} shipped", id)`, never string interpolation, so the
  values stay fields a log search can filter on. Levels come from configuration
  (`Logging__LogLevel__Default`). No secret, token, or personal data in a log line. Where
  logs go: the journal on Linux (`AddSystemd`), the Windows Event Log on IIS (the default
  builder adds it, warnings and up), the container's output in Docker. For JSON console
  output, set `Logging__Console__FormatterName=json` on that host.
- **The startup log line with the version** shows in every host's log which build is
  running, which is the first question after a deploy.
- .NET 10 makes the top-level `Program` class public, so tests can use
  `WebApplicationFactory<Program>` without a `public partial class Program` line.

## 4. Code that holds up under load

- **Async all the way.** Never `.Result`, `.Wait()`, or `.GetAwaiter().GetResult()` in
  request code: each one holds a thread-pool thread while it waits, and under load the
  pool runs dry and every request stalls.
- **Pass the `CancellationToken`.** A minimal API handler gets one by adding a
  `CancellationToken` parameter; it fires when the client goes away. Pass it to every EF
  Core and `HttpClient` call.
- **`HttpClient` from the factory.** A typed client
  (`builder.Services.AddHttpClient<PaymentsClient>(...)`) with its base address from
  options. Never `new HttpClient()` per call: each one holds a socket after it is
  disposed, and under load the host runs out. Add `AddStandardResilienceHandler()`
  (`Microsoft.Extensions.Http.Resilience`) for timeouts and retries on outside calls.
- **`DbContext` is scoped:** one per request through DI, never a singleton, never shared
  between threads.

## 5. EF Core migrations

Migrations run as a pipeline job before the deploy, from an idempotent SQL script. Never
at startup.

```
dotnet tool restore                          # dotnet-ef, pinned in .config/dotnet-tools.json
dotnet ef migrations add AddOrderStatus --project src/Orders.Api
dotnet ef migrations has-pending-model-changes --project src/Orders.Api
dotnet ef migrations script --idempotent --project src/Orders.Api --output migrations.sql
```

- **Why not `Database.Migrate()` at startup:** two hosts start together and race; the app's
  database account then needs rights to change the schema; a failed migration makes the
  app crash and restart in a loop; and nobody sees the SQL before it runs. Not
  `EnsureCreated()` either: it skips migrations completely.
- **In the pipeline** (the jobs live in `ci-templates`, `gitlab-ci` skill): the build job
  writes `migrations.sql` as an artifact next to the app. A migrate job per environment
  runs it before that environment's deploy, with a migration account that may change the
  schema. The app's own account may only read and write data. Run the script with
  `sqlcmd -b -i migrations.sql` (SQL Server) or `psql -v ON_ERROR_STOP=1 -f
  migrations.sql` (Postgres), so the first error stops it.
- **`--idempotent`** checks `__EFMigrationsHistory` before each migration, so the same
  script runs on staging, on prod, and again after a failure, and applies only what is
  missing.
- **`has-pending-model-changes`** in the test job fails when someone changed the model and
  forgot the migration.
- **Expand, then contract.** Staging runs the new schema with the new app while prod still
  runs the old app on the old one, and a rollback redeploys the old app onto the new
  schema. So each migration must work with the app version before it: add a column as
  nullable or with a default; rename by adding the new column, copying, and dropping the
  old one in a later release. Down migrations are never run in prod.
- The migrations, the `DbContext`, and `Microsoft.EntityFrameworkCore.Design` (with
  `PrivateAssets="all"`) live in the app project. Generating the script needs no database.
- Review a migration that rewrites or locks a large table with `sql-review` before it
  merges.

## 6. Tests

xUnit v3 with `WebApplicationFactory`, which starts the real app in memory with its real
pipeline, configuration, and DI.

```xml
<!-- tests/Orders.Api.Tests/Orders.Api.Tests.csproj -->
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <!-- xUnit v3 test projects are programs. -->
    <OutputType>Exe</OutputType>
    <IsPackable>false</IsPackable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" />
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="xunit.v3" />
    <PackageReference Include="xunit.runner.visualstudio" />
    <!-- The CI test job writes a JUnit report for the merge request. -->
    <PackageReference Include="JunitXml.TestLogger" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\Orders.Api\Orders.Api.csproj" />
    <Using Include="Xunit" />
  </ItemGroup>
</Project>
```

```csharp
public sealed class OrdersApiFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        // As on the servers: Production, with every required setting given here.
        builder.UseEnvironment("Production");
        builder.ConfigureAppConfiguration(config => config.AddInMemoryCollection(
            new Dictionary<string, string?> { ["Orders:PaymentsUrl"] = "https://payments.test" }));
    }
}

public sealed class ApiTests(OrdersApiFactory factory) : IClassFixture<OrdersApiFactory>
{
    [Fact]
    public async Task Health_answers_200()
    {
        using var client = factory.CreateClient();
        using var response = await client.GetAsync("/health", TestContext.Current.CancellationToken);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public void Start_fails_without_the_payments_url()
    {
        using var broken = factory.WithWebHostBuilder(builder => builder.ConfigureAppConfiguration(config =>
            config.AddInMemoryCollection(new Dictionary<string, string?> { ["Orders:PaymentsUrl"] = "" })));
        var error = Record.Exception(() => broken.CreateClient());
        Assert.NotNull(error);
        Assert.Contains("PaymentsUrl", error.ToString(), StringComparison.Ordinal);
    }
}
```

- **`WebApplicationFactory` runs the app as `Development`** unless told otherwise, so it
  reads `appsettings.Development.json` and a test passes on a value prod never has. Set
  `Production` and give the required settings in the factory.
- **Swap services with `ConfigureTestServices`** (an outside client, the clock), not by
  changing `Program.cs` for tests.
- **Test the database with the real engine,** not the EF Core InMemory provider. It has no
  transactions, no constraints, and no SQL, so a query that fails on the server passes.
- **`TestContext.Current.CancellationToken`** goes to every call that takes a token. The
  xUnit v3 analyzer warns without it, and warnings are errors here.
- Worth a test each: the health endpoint, a missing setting that stops the start, each
  endpoint's success and its 404 or 400, and that a protected endpoint answers 401 without
  a login.

## 7. Publish once, run in three places

The build job runs one publish (`gitlab-ci`, section 3):

```
dotnet publish src/Orders.Api/Orders.Api.csproj --configuration Release --output publish -p:RestoreLockedMode=true
```

```xml
<!-- src/Orders.Api/Orders.Api.csproj -->
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <!-- One portable folder for IIS, systemd, and the image: started as dotnet Orders.Api.dll everywhere. -->
    <UseAppHost>false</UseAppHost>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.Extensions.Hosting.Systemd" />
  </ItemGroup>
</Project>
```

- **Framework-dependent and portable:** no `--runtime`, no `--self-contained`. That folder
  runs on Windows and Linux wherever the 10.0 runtime is. `UseAppHost` off means no
  native launcher for the build machine's OS, so every host starts it the same way.

### IIS with Web Deploy

- Publish writes a `web.config` for the ASP.NET Core Module:
  `<aspNetCore processPath="dotnet" arguments=".\Orders.Api.dll" hostingModel="inprocess" />`.
  Keep the generated one. For IIS settings (request limits), commit a `web.config` in the
  project; publish adds the module's lines to it.
- The deploy job syncs the folder to the site with `msdeploy -verb:sync
  -source:contentPath=…` and the AppOffline rule, which stops the app so its DLLs are not
  locked (`gitlab-ci`, section 5). No Web Deploy package: building one needs Windows, and
  the build runs on Linux.
- The site's application pool runs with No Managed Code, one app per pool (in-process
  hosting allows only one). The pool's identity needs read access to the site folder, and
  nothing more; the app writes logs and uploads outside it, because a sync deletes what the
  build does not have.
- A start failure shows as HTTP 500.30 with the cause in the Windows Event Log
  (Application, source IIS AspNetCore Module V2).

### Linux with systemd behind nginx

Ansible writes the unit (`ansible` skill, section 5). The deploy job copies the folder to
`/opt/orders/releases/<sha>`, points `current` at it, and restarts the service.

```ini
# /etc/systemd/system/orders.service
[Unit]
Description=orders
Wants=network-online.target
After=network-online.target

[Service]
# With AddSystemd() in Program.cs, systemctl restart returns once the app has started.
Type=notify
User=orders
WorkingDirectory=/opt/orders/current
ExecStart=/usr/bin/dotnet /opt/orders/current/Orders.Api.dll
Environment=ASPNETCORE_URLS=http://127.0.0.1:5000
# App settings and secrets: a root-only file (mode 0600).
EnvironmentFile=/etc/orders/orders.env
Restart=always
RestartSec=5
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
```

- **Its own user,** with no login and no write access to `/opt/orders`. Kestrel listens on
  loopback only; nginx in front is the only way in.
- **`Type=notify` needs `AddSystemd()`** in the app; without it systemd waits for a ready
  message that never comes and kills the app after 90 seconds. With `Type=simple`, the
  restart returns at once and the deploy's health check retries until the app answers.
- nginx: `proxy_pass http://127.0.0.1:5000;` with `X-Forwarded-For` and
  `X-Forwarded-Proto` set, which `UseForwardedHeaders` reads.

### Docker

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0.404 AS build
WORKDIR /src
COPY global.json Directory.Build.props Directory.Packages.props ./
COPY src/Orders.Api/Orders.Api.csproj src/Orders.Api/packages.lock.json src/Orders.Api/
RUN dotnet restore src/Orders.Api/Orders.Api.csproj --locked-mode
COPY src/ src/
# The image build has no .git; the pipeline passes the sha for the version.
ARG CI_COMMIT_SHA
RUN dotnet publish src/Orders.Api/Orders.Api.csproj --configuration Release --no-restore --output /app

FROM mcr.microsoft.com/dotnet/aspnet:10.0.15
# The runtime image has no HTTP client for the health check.
RUN apt-get update \
    && apt-get install --yes --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app ./
USER $APP_UID
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=3 \
    CMD ["curl", "--fail", "--silent", "--output", "/dev/null", "http://127.0.0.1:8080/health"]
ENTRYPOINT ["dotnet", "Orders.Api.dll"]
```

- **Restore before the source is copied,** so a code change reuses the restore layer. The
  lock file makes the image's packages the ones CI tested.
- **Non-root:** the .NET images have an `app` user, and `$APP_UID` is its number. The app's
  files stay owned by root, so the app cannot change its own code.
- The images listen on 8080 (`ASPNETCORE_HTTP_PORTS`). Environment values come from the
  compose file's `env_file` on the host, never from `ENV` or `ARG` in the Dockerfile.
- The pipeline builds this image once, on `main`, and deploys it by digest
  (`gitlab-ci`, section 5). The compose file that runs it on a host is in `docker`
  (section 4); `docker-review` checks both.
- `.dockerignore` keeps `bin/`, `obj/`, `.git`, `tests/`, and local `.env` files out of the
  build.

## Before calling it done

```
dotnet build
dotnet test --configuration Release
dotnet publish src/<App>/<App>.csproj --configuration Release --output publish
dotnet list package --vulnerable --include-transitive
docker build --build-arg CI_COMMIT_SHA=$(git rev-parse HEAD) .   # Docker path only
```

- The build has no warnings, because each one is an error.
- The lock files are committed and match: `dotnet restore --locked-mode` passes.
- `dotnet publish/<App>.dll` starts with the environment variables a host would set, and
  `curl --fail http://localhost:5000/health` answers 200. Without them, it stops at
  start with the name of the missing setting.
- `grep -ri password src/*/appsettings*.json` finds nothing.

Then run the `dotnet-reviewer` agent on the change (in Codex, the `dotnet-review` skill).
