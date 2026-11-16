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
