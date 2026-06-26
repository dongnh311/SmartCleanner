using MacCleaner.Win.Core.Storage;
using Microsoft.Win32;
using Xunit;

namespace MacCleaner.Win.Tests;

public class LanguageServiceTests
{
    [Fact]
    public void SetCode_RoundTrips()
    {
        var sub = @"Software\MacCleaner_Test_" + Guid.NewGuid().ToString("N");
        var svc = new LanguageService(sub);
        try
        {
            Assert.Equal("", svc.Code);

            svc.SetCode("vi");
            Assert.Equal("vi", svc.Code);

            svc.SetCode("en");
            Assert.Equal("en", svc.Code);
        }
        finally
        {
            try { Registry.CurrentUser.DeleteSubKey(sub, throwOnMissingSubKey: false); } catch { /* best effort */ }
        }
    }
}
