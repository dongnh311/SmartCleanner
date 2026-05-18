namespace MacCleaner.Win.Core.FileSystem;

/// <summary>
/// Byte/byte-rate formatting helpers. Mirrors macOS Core/FileSystem/Bytes.swift
/// so UI strings stay identical across platforms ("5 MB", "47 KB/s").
/// </summary>
public static class Bytes
{
    /// <summary>Human-friendly bytes — "0 B", "5 MB", "1.2 GB".</summary>
    public static string Format(long bytes)
    {
        if (bytes < 1024) return $"{bytes} B";
        double v = bytes;
        string[] units = ["KB", "MB", "GB", "TB", "PB"];
        int i = -1;
        do
        {
            v /= 1024;
            i++;
        } while (v >= 1024 && i < units.Length - 1);
        return v >= 100 ? $"{v:F0} {units[i]}" : $"{v:F1} {units[i]}";
    }

    /// <summary>Compact rate label for tiles: "0", "47K", "5M".</summary>
    public static string FormatRate(ulong bytesPerSec)
    {
        double v = bytesPerSec;
        if (v < 1024) return "0";
        if (v < 1024 * 1024) return $"{(int)Math.Round(v / 1024)}K";
        return $"{(int)Math.Round(v / (1024 * 1024))}M";
    }

    /// <summary>Verbose rate: "0 B/s", "47 KB/s", "5 MB/s".</summary>
    public static string FormatRateVerbose(ulong bytesPerSec)
    {
        double v = bytesPerSec;
        if (v < 1024) return $"{(int)v} B/s";
        if (v < 1024 * 1024) return $"{v / 1024:F0} KB/s";
        return $"{v / (1024 * 1024):F0} MB/s";
    }
}
