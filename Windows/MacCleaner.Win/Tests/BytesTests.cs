using MacCleaner.Win.Core.FileSystem;
using Xunit;

namespace MacCleaner.Win.Tests;

public class BytesTests
{
    [Theory]
    [InlineData(0, "0 B")]
    [InlineData(1023, "1023 B")]
    [InlineData(1024, "1.0 KB")]
    [InlineData(1536, "1.5 KB")]
    [InlineData(1_048_576, "1.0 MB")]
    [InlineData(157_286_400, "150 MB")]
    public void Format_MatchesMacOSOutput(long bytes, string expected)
    {
        Assert.Equal(expected, Bytes.Format(bytes));
    }

    [Theory]
    [InlineData(0UL, "0")]
    [InlineData(1023UL, "0")]
    [InlineData(48_128UL, "47K")]
    [InlineData(5_242_880UL, "5M")]
    public void FormatRate_MatchesCompactForm(ulong bps, string expected)
    {
        Assert.Equal(expected, Bytes.FormatRate(bps));
    }
}
