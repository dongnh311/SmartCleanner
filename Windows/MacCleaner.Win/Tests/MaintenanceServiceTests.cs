using MacCleaner.Win.Core.Performance;
using Xunit;

namespace MacCleaner.Win.Tests;

public class MaintenanceServiceTests
{
    [Fact]
    public void All_CommandsAreWellFormedAndUnique()
    {
        Assert.NotEmpty(MaintenanceCommand.All);
        Assert.All(MaintenanceCommand.All, c =>
        {
            Assert.False(string.IsNullOrWhiteSpace(c.Id));
            Assert.False(string.IsNullOrWhiteSpace(c.Title));
            Assert.False(string.IsNullOrWhiteSpace(c.FileName));
        });
        var ids = MaintenanceCommand.All.Select(c => c.Id).ToList();
        Assert.Equal(ids.Count, ids.Distinct().Count());
    }

    [Fact]
    public void IsAvailable_TrueForSystemTool_FalseForBogus()
    {
        var svc = new MaintenanceService();
        var real = new MaintenanceCommand("t", "t", "t", "cmd", "/c echo", false, MaintenanceCategory.Shell);
        var bogus = new MaintenanceCommand("b", "b", "b", "definitely_not_a_real_tool_xyz", "", false, MaintenanceCategory.Shell);
        Assert.True(svc.IsAvailable(real));
        Assert.False(svc.IsAvailable(bogus));
    }

    [Fact]
    public void DisplayCommand_JoinsFileNameAndArguments()
    {
        var c = new MaintenanceCommand("x", "x", "x", "ipconfig", "/flushdns", false, MaintenanceCategory.Network);
        Assert.Equal("ipconfig /flushdns", c.DisplayCommand);
    }
}
