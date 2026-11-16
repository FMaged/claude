using System.Net;

namespace Orders.Api.Tests;

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
    public async Task Known_order_answers_200()
    {
        using var client = factory.CreateClient();
        var order = await client.GetFromJsonAsync<Order>("/orders/1", TestContext.Current.CancellationToken);
        Assert.Equal(1, order?.Id);
    }

    [Fact]
    public async Task Unknown_order_answers_404()
    {
        using var client = factory.CreateClient();
        using var response = await client.GetAsync("/orders/999", TestContext.Current.CancellationToken);
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
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
