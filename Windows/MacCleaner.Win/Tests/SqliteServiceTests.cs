using MacCleaner.Win.Core.Storage;
using Microsoft.Data.Sqlite;
using Xunit;

namespace MacCleaner.Win.Tests;

public class SqliteServiceTests
{
    [Fact]
    public void OpenConnection_CreatesSchema_AndIsWritable()
    {
        var svc = new SqliteService();
        using var conn = svc.OpenConnection();

        using var cmd = conn.CreateCommand();
        cmd.CommandText = "INSERT OR REPLACE INTO cpu_samples (ts, percent) VALUES ($ts, $p);";
        cmd.Parameters.AddWithValue("$ts", DateTimeOffset.UtcNow.ToUnixTimeSeconds());
        cmd.Parameters.AddWithValue("$p", 12.34);
        int affected = cmd.ExecuteNonQuery();
        Assert.Equal(1, affected);

        using var read = conn.CreateCommand();
        read.CommandText = "SELECT COUNT(*) FROM cpu_samples;";
        long count = Convert.ToInt64(read.ExecuteScalar());
        Assert.True(count >= 1);
    }
}
