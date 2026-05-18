using MacCleaner.Win.Core.Applications;
using MacCleaner.Win.Core.Cleanup;
using MacCleaner.Win.Core.FileSystem;
using MacCleaner.Win.Core.Performance;
using MacCleaner.Win.Core.Storage;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace MacCleaner.Win.Core.DI;

/// <summary>
/// Composition root for Core services. The App layer adds its own
/// platform-bound services (e.g. ToastService that needs WindowsAppSDK)
/// in a separate extension method after calling this one.
/// </summary>
public static class AppContainer
{
    public static IServiceCollection AddCoreServices(this IServiceCollection services)
    {
        services.AddLogging(builder =>
        {
            builder.AddDebug();
            builder.SetMinimumLevel(LogLevel.Information);
        });

        services.AddSingleton<ISystemMetricsService, SystemMetricsService>();
        services.AddSingleton<IProcessService, ProcessService>();
        services.AddSingleton<IBatteryService, BatteryService>();
        services.AddSingleton<INetworkService, NetworkService>();
        services.AddSingleton<IDiskMonitorService, DiskMonitorService>();
        services.AddSingleton<IBluetoothService, BluetoothService>();
        services.AddSingleton<ISensorsService, SensorsService>();
        services.AddSingleton<IDriveService, DriveService>();
        services.AddSingleton<IRegistryService, RegistryService>();
        services.AddSingleton<ISqliteService, SqliteService>();
        services.AddSingleton<IWingetService, WingetService>();
        services.AddSingleton<ICleanupService, CleanupService>();
        services.AddSingleton<IRecycleBinService, RecycleBinService>();

        return services;
    }
}
