using System.Globalization;

namespace MemoryGraph.Storage;

public sealed partial class MemoryStore
{
    private static string FormatDate(DateTime date)
    {
        return date.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture);
    }

    private static DateTime ParseDate(string value)
    {
        return DateTime.Parse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind);
    }
}
