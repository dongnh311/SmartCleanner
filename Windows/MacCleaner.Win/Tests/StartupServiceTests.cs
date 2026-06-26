using MacCleaner.Win.Core.Storage;
using Xunit;

namespace MacCleaner.Win.Tests;

public class StartupServiceTests
{
    [Fact]
    public void SetEnabled_AddsAndRemovesRunEntry()
    {
        // Unique value name + fake path so we never touch the real entry and
        // leave nothing behind on the CI runner.
        var name = "MacCleaner_Test_" + Guid.NewGuid().ToString("N");
        var svc = new StartupService(name, () => @"C:\fake\MacCleaner.exe");
        try
        {
            Assert.False(svc.IsEnabled);

            svc.SetEnabled(true);
            Assert.True(svc.IsEnabled);

            svc.SetEnabled(false);
            Assert.False(svc.IsEnabled);
        }
        finally
        {
            svc.SetEnabled(false);
        }
    }

    [Fact]
    public void SetEnabled_True_WithEmptyPath_IsNoOp()
    {
        var name = "MacCleaner_Test_" + Guid.NewGuid().ToString("N");
        var svc = new StartupService(name, () => null);
        svc.SetEnabled(true);
        Assert.False(svc.IsEnabled);
    }
}
