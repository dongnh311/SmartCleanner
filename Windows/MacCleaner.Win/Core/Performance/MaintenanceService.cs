using System.Diagnostics;

namespace MacCleaner.Win.Core.Performance;

public sealed record MaintenanceResult(bool Success, string Output);

/// <summary>
/// Runs <see cref="MaintenanceCommand"/>s from inside the app. Admin commands
/// elevate through the native UAC prompt (ShellExecute + the "runas" verb) —
/// no service or scheduled task needed. Because ShellExecute can't redirect
/// output, elevated commands report exit status only; non-admin commands run
/// in-process with captured output.
/// </summary>
public interface IMaintenanceService
{
    /// <summary>True when the command's executable ships on this machine.</summary>
    bool IsAvailable(MaintenanceCommand command);

    Task<MaintenanceResult> RunAsync(MaintenanceCommand command);
}

public sealed class MaintenanceService : IMaintenanceService
{
    public bool IsAvailable(MaintenanceCommand command)
    {
        var exe = command.FileName.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)
            ? command.FileName
            : command.FileName + ".exe";
        return File.Exists(Path.Combine(Environment.SystemDirectory, exe));
    }

    public Task<MaintenanceResult> RunAsync(MaintenanceCommand command) =>
        command.RequiresAdmin ? RunElevatedAsync(command) : RunCapturedAsync(command);

    private static async Task<MaintenanceResult> RunElevatedAsync(MaintenanceCommand command)
    {
        var psi = new ProcessStartInfo
        {
            FileName = command.FileName,
            Arguments = command.Arguments,
            UseShellExecute = true,   // required for the "runas" elevation verb
            Verb = "runas",
        };
        try
        {
            using var process = Process.Start(psi);
            if (process is null) return new MaintenanceResult(false, "Could not start the command.");
            await process.WaitForExitAsync();
            return process.ExitCode == 0
                ? new MaintenanceResult(true, "Completed successfully.")
                : new MaintenanceResult(false, $"Exited with code {process.ExitCode}.");
        }
        catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 1223)
        {
            return new MaintenanceResult(false, "Cancelled at the UAC prompt.");
        }
        catch (Exception ex)
        {
            return new MaintenanceResult(false, ex.Message);
        }
    }

    private static async Task<MaintenanceResult> RunCapturedAsync(MaintenanceCommand command)
    {
        var psi = new ProcessStartInfo
        {
            FileName = command.FileName,
            Arguments = command.Arguments,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };
        try
        {
            using var process = Process.Start(psi);
            if (process is null) return new MaintenanceResult(false, "Could not start the command.");
            var stdout = await process.StandardOutput.ReadToEndAsync();
            var stderr = await process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync();

            var ok = process.ExitCode == 0;
            var text = (ok ? stdout : (string.IsNullOrWhiteSpace(stderr) ? stdout : stderr)).Trim();
            if (text.Length == 0) text = ok ? "Done." : $"Exited with code {process.ExitCode}.";
            return new MaintenanceResult(ok, text);
        }
        catch (Exception ex)
        {
            return new MaintenanceResult(false, ex.Message);
        }
    }
}
