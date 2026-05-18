using MacCleaner.Win.Core.Storage;
using Xunit;

namespace MacCleaner.Win.Tests;

public class RegistryServiceTests
{
    [Fact]
    public void ListInstalledPrograms_ReturnsAtLeastOne_OnWindowsRunner()
    {
        // CI runner is a full Windows install — Uninstall key always has
        // dozens of entries. Smoke test: we can read at least one.
        var svc = new RegistryService();
        var programs = svc.ListInstalledPrograms();
        Assert.NotEmpty(programs);
        Assert.All(programs, p => Assert.False(string.IsNullOrWhiteSpace(p.DisplayName)));
    }

    [Fact]
    public void ListLoginItems_DoesNotThrow()
    {
        var svc = new RegistryService();
        // Whether the user has any Run entries is environment-specific —
        // we only assert the call returns without throwing.
        var items = svc.ListLoginItems();
        Assert.NotNull(items);
    }
}
