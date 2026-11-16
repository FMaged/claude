---
name: dotnet-review
description: Use when reviewing a C# ASP.NET Core app on .NET — Program.cs, controllers and minimal API handlers, services, appsettings files, .csproj and Directory.*.props files, EF Core queries and migrations, or the tests (e.g. "review my C# code", "check this controller before I merge", "is this .NET API ready for production?", "why does the app stall under load?", "does anything here leak a secret or block a thread?", "is this EF Core migration safe to run before the deploy?"). Reports what leaks, what blocks a thread, what breaks in production or on another host, what is untested, and which packages are unpinned or vulnerable, with the file and line. Not for .NET Framework 4.x or desktop apps.
---

# .NET Review

Review the C# code, `Program.cs`, `appsettings*.json`, `Properties/launchSettings.json`,
the `.csproj`, `Directory.Build.props`, `Directory.Packages.props`, `global.json`,
`nuget.config`, the EF Core migrations, and the test projects. Report problems. Do not
rewrite unless the user asks.

The usual production failures in a .NET app are quiet. A `.Result` works on a laptop and
stalls every request under load. A migration at startup works on one host and races on
two. A setting baked into the artifact works on staging and is wrong on prod. What matters
most: no secret or exception detail leaves the app, no request holds a thread while it
waits, and the one artifact the pipeline built runs unchanged in every environment and on
every host kind (IIS, systemd behind nginx, Docker). The writing rules are in the `dotnet`
skill.

Other reviews own their part: who may call what (authorization, login, CORS, uploads)
is `web-security-review`; the SQL a query sends and a migration that locks a big table
are `sql-review`; the Dockerfile is `docker-review`; the pipeline is `gitlab-ci-review`.
Name them where a finding needs them, and stay on the .NET side.

## 0. Read the build first

- **Resolve each project's settings before you flag what it lacks.** `Directory.Build.props`
  applies to every project below it, and a project's `.csproj` can override it
  (`<TreatWarningsAsErrors>false</TreatWarningsAsErrors>`, `<NoWarn>`). A second
  `Directory.Build.props` lower down (in `tests/`) **replaces** the root one unless it
  imports it, so those projects silently lose every root setting:
  `<Import Project="$([MSBuild]::GetPathOfFileAbove('Directory.Build.props', '$(MSBuildThisFileDirectory)../'))" />`.
- **The target framework.** `net10.0` is the current LTS. `net8.0` and `net9.0` left
  support on 10 November 2026 and get no more security fixes; anything older long before.
  Should fix, with the upgrade as its own task.
- **Which hosts run it:** a `web.config` or IIS deploy job, a systemd unit, a
  `Dockerfile`. Forwarded headers, logs, file paths, and ports depend on it (section 5).
- In a diff, read the whole method and its registration in `Program.cs`, not only the
  changed lines: a lifetime, a middleware order, or a missing `await` is often outside the
  hunk.

## 1. What leaks

- **A secret in the repo:** a password, API key, client secret, signing key, or a
  connection string with `Password=` or `Pwd=`, in any `appsettings*.json`
  (`appsettings.Development.json` included), `launchSettings.json`, a committed `.env`, a
  publish profile (`*.pubxml`), `nuget.config` (`ClearTextPassword`), or code. Anyone who
  can read the repo has it. Blocker. A `UserSecretsId` is an id, not a secret, and a
  connection string with `Integrated Security=true` and no password is fine.
- **Exception details to clients:**
  - `app.UseDeveloperExceptionPage()` outside `if (app.Environment.IsDevelopment())`.
    The default builder turns it on in Development by itself.
  - `ex.Message`, `ex.ToString()`, or `ex.StackTrace` in a response:
    `BadRequest(ex.Message)`, `Results.Problem(ex.ToString())`, or a
    `CustomizeProblemDetails` that copies the exception. A database exception names
    tables, columns, and sometimes the server.
  - `ASPNETCORE_ENVIRONMENT=Development` set for a server (in a committed `web.config`, a
    unit file, a compose file). It turns the developer exception page on in production.

  Blocker.
- **EF Core logging values:** `EnableSensitiveDataLogging()` or `EnableDetailedErrors()`
  outside a Development check writes parameter values (passwords, personal data) to the
  log. Should fix; blocker if it is unconditional and the app handles credentials.
- **Logs that carry secrets or personal data:** a logged request body, an `Authorization`
  or cookie header, a whole options object or connection string, a token in a message.
  HTTP logging (`AddHttpLogging`) with `RequestBody` on, or with `Authorization` added to
  `RequestHeaders`, logs every login.
- **An EF entity returned as the response:** every column goes out, the password hash
  included. Bound as the request body, it lets a client set any column (overposting).
  Request and response records per endpoint. Hand the authorization side to
  `web-security-review`.
- **A health endpoint that says too much:** a custom `ResponseWriter` that writes check
  descriptions, exception messages, or server names, on an endpoint with no login.
- **OpenAPI in production:** `MapOpenApi()`, `UseSwagger()`, or `UseSwaggerUI()` outside
  a Development check publishes the whole API surface. Should fix, unless the API is
  public by design.
- **`TrustServerCertificate=True`** in a SQL Server connection string anywhere outside
  Development: the app no longer checks whose server it is talking to.

## 2. What blocks

A blocked thread-pool thread is invisible until load: then the pool runs dry, every
request waits, the health check times out, and the hosts restart one after another.

- **Sync over async in request code,** a hosted service, a middleware, or a DI factory:
  `.Result`, `.Wait()`, `.GetAwaiter().GetResult()`, `Task.WaitAll`, `SemaphoreSlim.Wait()`.
  Blocker on a request path. `await` it, and make the caller `async` up to the handler.
- **Synchronous I/O where an async form exists:** `ToList()`, `First()`, `SaveChanges()`,
  `File.ReadAllText`, `Stream.Read`, or `Thread.Sleep` in request code. Kestrel refuses
  synchronous reads of the request body by default; `AllowSynchronousIO = true` is the
  workaround that hides the problem. Should fix.
- **`async void`** anywhere but an event handler. An exception in it is not caught by
  anything and ends the process. Blocker. `async Task`.
- **Fire and forget in a request:** `_ = Task.Run(...)`, a call to an async method with no
  `await`, or `Task.Run` around work that uses the request's `DbContext` or other scoped
  services. They are disposed when the response ends, so the work fails with
  `ObjectDisposedException`, and a restart loses it. A queue read by a `BackgroundService`
  that creates its own scope.
- **`Task.Run` to make sync code look async** in a request: it moves the wait to another
  pool thread and frees nothing. Nit, unless it wraps blocking I/O.
- **No `CancellationToken`:** a handler without one, or one that takes it and does not pass
  it to EF Core, `HttpClient`, or `Task.Delay`. When the client goes away the query runs
  to the end anyway. `CancellationToken.None` passed on purpose needs a reason. Should fix.
- **`new HttpClient()` per call** or in a `using`: each one keeps its socket after it is
  disposed, and under load the host runs out of ports. Blocker on a request path. A
  `static` or singleton `HttpClient` without `PooledConnectionLifetime` never sees a DNS
  change; should fix. The fix for both: a typed client from `AddHttpClient<T>()`.
- **No timeout on an outside call.** `HttpClient` waits 100 seconds by default, so a slow
  dependency holds each request that long. `AddStandardResilienceHandler()` or a
  `Timeout` from options. Should fix.
- **A background loop that ignores `stoppingToken`,** or waits with `Thread.Sleep`: every
  stop and every deploy waits until the host kills the process. `await Task.Delay(delay,
  stoppingToken)`.

## 3. Service lifetimes and shared state

The default builder checks lifetimes only in Development. Production, and a test run as
Production, share the wrong instance between requests without a word.

- **A scoped service in a singleton:** a `DbContext`, a repository, or `IOptionsSnapshot<T>`
  injected into a class registered with `AddSingleton`, or into a hosted service. One
  `DbContext` then serves every request at once: "A second operation was started on this
  context instance", and changes from one request saved by another. Blocker. Inject
  `IServiceScopeFactory` and create a scope per unit of work.
- **A typed `HttpClient` injected into a singleton:** the client is meant to be
  short-lived, and the captured one never gets a new handler. Use `IHttpClientFactory` in
  the singleton, or register the consumer as transient or scoped.
- **Mutable static or singleton state** without thread safety: a `static Dictionary`, a
  `List<T>` in a singleton, a cached value written by requests. Parallel requests corrupt
  it. `ConcurrentDictionary`, `IMemoryCache`, or no shared state.
- **Per-user data in a singleton** (the current user, the tenant): one user's request sees
  another's. Blocker.
- To catch these in every environment, the app can turn the checks on:
  `builder.Host.UseDefaultServiceProvider(o => { o.ValidateScopes = true; o.ValidateOnBuild = true; });`.

## 4. What makes the artifact differ per environment

The pipeline builds once and deploys the same folder or image to staging and then prod
(`gitlab-ci`). Anything that bakes an environment into the build breaks that, and a
value fixed for prod then needs a rebuild that nobody tested. Blocker for each:

- `appsettings.Staging.json` or `appsettings.Production.json` with values that differ per
  environment (URLs, connection strings, feature switches).
- `#if PRODUCTION`, `#if STAGING`, or a build configuration per environment
  (`-c Staging`, a `Staging` configuration in the `.csproj`).
- `<EnvironmentName>` in the `.csproj` or a publish profile: publish writes
  `ASPNETCORE_ENVIRONMENT` into the `web.config`, so the artifact decides its environment.
- `<environmentVariables>` in a committed `web.config`. Every deploy overwrites it, and
  the values are in the artifact. They belong on the application pool.

Should fix:

- **Branches on the environment** beyond Development tools: `if (env.IsProduction())` or
  `IsEnvironment("Staging")` that change what the app does. Staging no longer tests what
  prod runs.
- **An environment value in `appsettings.json`:** a localhost connection string or URL as
  the default. A host where the variable is missing then quietly uses it, and on a server
  with a local SQL Server it may even connect. Local values go in
  `appsettings.Development.json`.
- **A setting checked on first use, not at start:** `Configure<T>(section)` without
  `ValidateOnStart()`, `configuration["Orders:PaymentsUrl"]` read in a handler, or a
  `?? "default"` that hides a missing value. The deploy's health check passes, and the
  first real request fails. `AddOptions<T>().BindConfiguration(...).ValidateDataAnnotations().ValidateOnStart()`.
- `IConfiguration` injected into business code instead of `IOptions<T>`. Nit.

## 5. What breaks at start, on deploy, or on another host

- **`Database.Migrate()`, `MigrateAsync()`, or `EnsureCreated()` at startup,** in
  `Program.cs`, a hosted service, or a `DbContext` constructor. Two hosts start together
  and race; the app's database account needs rights to change the schema; a failed
  migration crashes the app in a restart loop; nobody saw the SQL. `EnsureCreated()` also
  skips migrations completely. Blocker. An idempotent script run by a pipeline job
  (`dotnet`, section 5).
- **No `/health`,** or one that cannot fail: it does not check the database the app cannot
  work without (`AddDbContextCheck<T>()`), so a deploy with a wrong connection string
  passes. A check of an outside service the app can work without marks every host
  unhealthy at once when that service is down. Should fix.
- **`/health` behind a login:** an authorization `FallbackPolicy` covers every endpoint
  without its own metadata, health included, and the deploy's check gets 401.
  `.AllowAnonymous()` on `MapHealthChecks`. Should fix.
- **Forwarded headers:**
  - Behind nginx or a load balancer with no `UseForwardedHeaders()`: the app sees
    `http`, so `UseHttpsRedirection` loops and generated links are wrong, and every
    client has the proxy's address, so a per-IP rate limit blocks everyone at once.
  - `UseForwardedHeaders()` after other middleware: it must come first.
  - `KnownNetworks.Clear()` and `KnownProxies.Clear()` (or `KnownIPNetworks`) with
    nothing added back: any client can set `X-Forwarded-For` and pick its own address.
    Should fix; the address check belongs to `web-security-review` if limits or logs rely
    on it.
- **Writes inside the app folder:** logs, uploads, a SQLite file, or Data Protection keys
  under `ContentRootPath` or `AppContext.BaseDirectory`. The IIS sync deletes what the
  build does not have, a Linux deploy switches to a new release folder, and in Docker the
  folder belongs to root. Should fix: a path from configuration, outside the app.
- **Data Protection keys not shared:** an app with cookies, antiforgery, or
  `IDataProtector` that runs on two hosts or in a container, without
  `PersistKeysTo…` and `SetApplicationName`. Every deploy, and every second host, logs
  users out and fails their forms. Should fix.
- **A port or URL in code:** `app.Run("http://localhost:5000")`, `UseUrls(...)`, or
  `Listen(...)`. It overrides `ASPNETCORE_URLS` and `ASPNETCORE_HTTP_PORTS`, so the Docker
  image stops listening on 8080. Should fix.
- **A publish tied to one OS:** `<RuntimeIdentifier>`, `<SelfContained>true</SelfContained>`,
  or no `<UseAppHost>false</UseAppHost>` in the app project. The one folder must run on
  IIS and on Linux. Should fix.
- **Windows-only assumptions** in an app that also runs on Linux or Docker: a file name
  whose case differs from the file on disk (Linux is case-sensitive), `\` in a path instead
  of `Path.Combine`, `DateTime.Now` (the IIS host's time zone, UTC in the container),
  parsing or formatting without `CultureInfo.InvariantCulture` (the host's culture
  decides `1,5` or `1.5`), the registry, or Windows authentication with no plan for the
  other hosts. Should fix.
- **A `BackgroundService` whose loop has no `try`/`catch` per item:** one bad message
  throws out of `ExecuteAsync`, and the host stops the whole app. The opposite,
  `BackgroundServiceExceptionBehavior.Ignore`, leaves a dead worker in a healthy-looking
  app. Should fix.

## 6. Warnings switched off

Warnings are errors in every build (`dotnet`, section 1). Each of these hides a class of
bug. Should fix, unless the line says why:

- `<TreatWarningsAsErrors>` missing or `false`, at the root or in one project.
- `<NoWarn>` or `#pragma warning disable` for `CS4014` (a task not awaited, the fire and
  forget of section 2), nullable warnings (`CS86xx`), `CA2016` (a token not forwarded), or
  `NU1903` and `NU1904` (high and critical package advisories). The same codes in
  `WarningsNotAsErrors`.
- `<Nullable>disable</Nullable>`, or `!` used to silence a warning instead of handling the
  null. `= null!` on a property that is only set later.
- `<NuGetAudit>false</NuGetAudit>`, or `<NuGetAuditMode>direct</NuGetAuditMode>`, which
  stops reporting vulnerable packages that come in through other packages.
- `<AnalysisLevel>none</AnalysisLevel>` or `<EnableNETAnalyzers>false</EnableNETAnalyzers>`.
- A `NuGetAuditSuppress` item for an advisory with no comment on why it does not apply.

## 7. EF Core

- **SQL built from strings:** `FromSqlRaw`, `ExecuteSqlRaw`, or `SqlQueryRaw` with
  `$"..."` or `+`. That is SQL injection. Blocker. `FromSql($"... {id}")` and the other
  methods without `Raw` turn the holes into parameters.
- **A migration the running app cannot work with.** The migrate job runs before each
  deploy, so prod runs the old app on the new schema until its own deploy, and a rollback
  runs the old app on it for good. Blocker for: `DropColumn` or `DropTable` of something
  the previous release reads, `RenameColumn` or `RenameTable`, a column made `NOT NULL`
  without a default, or a type change. Expand, then contract in a later release.
- **An applied migration edited or deleted,** or the model snapshot regenerated. The
  idempotent script skips a migration by its id, so every database that already ran it
  never gets the change. Should fix: a new migration.
- **A model change with no migration.** `dotnet ef migrations has-pending-model-changes`
  in the test job catches it. Should fix.
- **Queries that grow with the data:**
  - A query inside a loop, or `UseLazyLoadingProxies()`: one query per row (N+1).
  - `ToList()` or `AsEnumerable()` before `Where` or `Select`: the whole table comes into
    memory.
  - A list endpoint with no paging.
  - Several collection `Include`s in one query with no `AsSplitQuery()`: the rows multiply.

  Should fix. `ToQueryString()` shows the SQL, which goes to `sql-review`.
- **Tracking where nothing is saved** on a large read: `AsNoTracking()`. Nit.
- A migration that rewrites or locks a large table: name it for `sql-review`.
- `Microsoft.EntityFrameworkCore.*` packages at different versions, which fail at run time
  with `MissingMethodException`. `Microsoft.EntityFrameworkCore.Design` without
  `PrivateAssets="all"` ships the design tools in the publish folder; nit.

## 8. What is untested

- **No test project,** or one the solution file does not include: `dotnet test` at the
  root, which the CI job runs, skips it. Should fix.
- **`WebApplicationFactory` without `UseEnvironment("Production")`:** the tests read
  `appsettings.Development.json` and pass on values prod never has. Should fix.
- **The EF Core InMemory provider or in-memory SQLite** standing in for SQL Server or
  Postgres: no constraints, no transactions, other SQL. A query that fails on the server
  passes. Should fix.
- **Tests that cannot fail:**
  - `Assert.ThrowsAsync` without `await`.
  - An `async void` test.
  - A `try`/`catch` that swallows the assertion.
  - A test with no assertion.
  - `[Fact(Skip = ...)]` with no issue named.
  - A category filter in CI that leaves tests out.

  Should fix.
- **Tests that depend on the outside:** a real outside API, a shared database, the clock
  (`DateTime.UtcNow` in the code under test; inject `TimeProvider`), `Task.Delay` to wait
  for something, or a running server at `localhost`. They fail at random, and people stop
  trusting the red. Should fix.
- **Paths with no test,** where they matter: the health endpoint, a missing required
  setting stopping the start, each endpoint's 404 and 400, a protected endpoint answering
  401 without a login and 403 with the wrong role, and the code the change touched. Name
  the missing tests; do not ask for coverage numbers.

## 9. Packages: unpinned or vulnerable

- **A known vulnerable package,** direct or transitive (`dotnet list package --vulnerable
  --include-transitive`). High or critical: blocker. Moderate or low: should fix.
- **No lock files,** `packages.lock.json` in `.gitignore`, or a CI restore without
  `--locked-mode` or `-p:RestoreLockedMode=true`. CI then resolves whatever is newest, not
  what was tested. Should fix.
- **Floating or open versions:** `10.*`, `[10.0,)`. Central package management refuses
  them unless `CentralPackageFloatingVersionsEnabled` is on. Should fix.
- **Versions outside `Directory.Packages.props`:** a `VersionOverride` in one project, so
  two projects run different versions of the same package. Should fix, unless the line
  says why.
- **`Microsoft.AspNetCore.*` 2.x packages** in a `net10.0` project. They are for .NET
  Framework, duplicate what the shared framework already has, and pull in old
  dependencies. Remove them; the framework reference covers it. Should fix.
- **Deprecated packages** (`dotnet list package --deprecated`): should fix when the
  package says it is unsafe or abandoned, nit otherwise.
- **A `nuget.config` with more than one feed** and no `<clear />` or
  `<packageSourceMapping>`: a public package with the same name as a private one can win.
  Should fix.
- **`global.json` missing,** or a `rollForward` of `major` or `latestMajor`: a build
  machine with a newer SDK builds with it. Nit, unless the pipeline image and the pin
  disagree.

## Commands

```
dotnet build --configuration Release
dotnet test --configuration Release
dotnet restore --locked-mode
dotnet list package --vulnerable --include-transitive
dotnet list package --deprecated
dotnet ef migrations has-pending-model-changes --project src/<App>
dotnet ef migrations script --idempotent --project src/<App> --output migrations.sql
grep -rniE 'password|pwd=|secret|apikey|api_key|ClearTextPassword' --include='appsettings*.json' --include='launchSettings.json' --include='*.pubxml' --include='nuget.config' .
grep -rnE '\.Result\b|\.Wait\(\)|GetAwaiter\(\)\.GetResult\(\)|async void|new HttpClient\(|Migrate(Async)?\(|EnsureCreated|(FromSql|ExecuteSql|SqlQuery)Raw' --include='*.cs' .
```

`dotnet list package` needs a restore first. The greps list lines to read, not findings:
`.Result` is also a property name (an action filter's `context.Result`). The first grep
prints the matching lines; when it finds a real secret, report the file and line and do
not copy the value into the report. Skip what the compiler and analyzers report on their
own when the build has warnings as errors; say "run `dotnet build`" in one line instead.

## How to report

Most serious first, as a list:

```
<file>:<line> — <blocker | should fix | nit>: <what is wrong and what it does in production>
Fix: <the change, one line>
```

A blocker leaks a secret or exception details, can stall or crash the app under load
(sync over async or `async void` on a request path, `HttpClient` per call, a scoped
service in a singleton), migrates at startup or ships a migration the running release
cannot use, bakes an environment into the artifact, lets SQL be injected, or ships a
high or critical vulnerable package. A should-fix fails later or only sometimes: a
missing cancellation token, a setting checked on first use, a health check that cannot
see the database, a warning switched off, an unpinned package, a test that cannot fail.
A nit is tidiness. If the code is fine, say so in one sentence and name the two or three
things you checked hardest. Do not invent findings to fill a list. If you add a comment
as part of a fix, follow the `code-comments` skill.
