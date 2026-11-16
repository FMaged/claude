using Microsoft.AspNetCore.Mvc.Testing;

namespace Orders.Api.Tests;

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
