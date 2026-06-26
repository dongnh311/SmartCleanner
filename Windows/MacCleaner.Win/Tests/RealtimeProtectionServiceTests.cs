using MacCleaner.Win.Core.Protection;
using MacCleaner.Win.Core.Tools;
using Xunit;

namespace MacCleaner.Win.Tests;

public class RealtimeProtectionServiceTests
{
    [Fact]
    public void IsCanaryTampered_OnlyTrueOnRealChange()
    {
        var dir = Path.Combine(Path.GetTempPath(), "mc_canary_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        var path = Path.Combine(dir, "canary.txt");
        const string expected = "untouched-canary-body";
        try
        {
            File.WriteAllText(path, expected);
            Assert.False(RealtimeProtectionService.IsCanaryTampered(path, expected)); // untouched

            File.WriteAllText(path, "encrypted-by-ransomware");
            Assert.True(RealtimeProtectionService.IsCanaryTampered(path, expected));  // content changed

            File.Delete(path);
            Assert.True(RealtimeProtectionService.IsCanaryTampered(path, expected));  // deleted
        }
        finally
        {
            try { Directory.Delete(dir, recursive: true); } catch { /* best effort */ }
        }
    }

    [Fact]
    public void Service_ConstructsIdle_WithSignatures()
    {
        var svc = new RealtimeProtectionService(new MalwareHashStore(), new QuarantineService());
        Assert.True(svc.SignatureCount >= 1);
        Assert.False(svc.IsRunning);
        Assert.Empty(svc.RecentEvents);
    }
}
