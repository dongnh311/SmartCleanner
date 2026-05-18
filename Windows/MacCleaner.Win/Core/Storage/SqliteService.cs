using Microsoft.Data.Sqlite;

namespace MacCleaner.Win.Core.Storage;

public interface ISqliteService
{
    /// <summary>Open a fresh connection to the user-state DB.
    /// Schema migrations are applied lazily on the first call.</summary>
    SqliteConnection OpenConnection();

    /// <summary>Absolute path of the SQLite file on disk (for debugging).</summary>
    string DatabasePath { get; }
}

/// <summary>
/// Mirrors the role of macOS <c>AppDatabase.swift</c> (GRDB) — owns the
/// usage-trend DB lifecycle. Stored under <c>%LOCALAPPDATA%\MacCleaner\</c>
/// since the app is unpackaged (no LocalApplicationData per-package
/// folder); writable for the current user, survives reinstalls.
/// </summary>
public sealed class SqliteService : ISqliteService
{
    private readonly object _migrateLock = new();
    private bool _migrated;

    public string DatabasePath { get; }

    public SqliteService()
    {
        var baseDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MacCleaner");
        Directory.CreateDirectory(baseDir);
        DatabasePath = Path.Combine(baseDir, "trends.sqlite");
    }

    public SqliteConnection OpenConnection()
    {
        EnsureMigrated();
        var cs = new SqliteConnectionStringBuilder
        {
            DataSource = DatabasePath,
            Mode = SqliteOpenMode.ReadWriteCreate
        }.ToString();
        var conn = new SqliteConnection(cs);
        conn.Open();
        return conn;
    }

    private void EnsureMigrated()
    {
        if (_migrated) return;
        lock (_migrateLock)
        {
            if (_migrated) return;
            using var conn = new SqliteConnection($"Data Source={DatabasePath}");
            conn.Open();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = """
                CREATE TABLE IF NOT EXISTS cpu_samples (
                    ts        INTEGER PRIMARY KEY,
                    percent   REAL    NOT NULL
                );
                CREATE TABLE IF NOT EXISTS memory_samples (
                    ts            INTEGER PRIMARY KEY,
                    used_bytes    INTEGER NOT NULL,
                    total_bytes   INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS disk_samples (
                    ts            INTEGER NOT NULL,
                    volume        TEXT    NOT NULL,
                    used_bytes    INTEGER NOT NULL,
                    total_bytes   INTEGER NOT NULL,
                    PRIMARY KEY (ts, volume)
                );
                """;
            cmd.ExecuteNonQuery();
            _migrated = true;
        }
    }
}
