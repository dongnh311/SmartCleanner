using MacCleaner.Win.Core.FileSystem;
using Xunit;

namespace MacCleaner.Win.Tests;

public class DriveServiceTests
{
    [Fact]
    public void List_ReturnsAtLeastOneDrive_OnWindowsRunner()
    {
        // The CI runner always has at least the C: system volume mounted.
        // This is a smoke test — verifies the WMI/DriveInfo path doesn't throw.
        var svc = new DriveService();
        var drives = svc.List();
        Assert.NotEmpty(drives);
        Assert.Contains(drives, d => d.IsReady);
    }
}
