using System.ComponentModel.DataAnnotations;

namespace Orders.Api;

public sealed class OrdersOptions
{
    public const string Section = "Orders";

    // Differs per environment, so it comes from the host: Orders__PaymentsUrl.
    [Required, Url]
    public string PaymentsUrl { get; init; } = "";

    [Range(1, 500)]
    public int PageSize { get; init; } = 50;
}
