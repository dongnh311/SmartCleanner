using MacCleaner.Win.Core.Applications;
using MacCleaner.Win.Core.Cleanup;
using MacCleaner.Win.Core.Files;
using MacCleaner.Win.Core.FileSystem;
using MacCleaner.Win.Core.Performance;
using MacCleaner.Win.Core.Protection;
using MacCleaner.Win.Core.Storage;
using MacCleaner.Win.Core.Tools;
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
        services.AddSingleton<IMaintenanceService, MaintenanceService>();
        services.AddSingleton<IDriveService, DriveService>();
        services.AddSingleton<IRegistryService, RegistryService>();
        services.AddSingleton<IStartupService, StartupService>();
        services.AddSingleton<ILanguageService, LanguageService>();
        services.AddSingleton<ISqliteService, SqliteService>();
        services.AddSingleton<IWingetService, WingetService>();
        services.AddSingleton<ICleanupService, CleanupService>();
        services.AddSingleton<IRecycleBinService, RecycleBinService>();
        services.AddSingleton<ISpaceLensService, SpaceLensService>();
        services.AddSingleton<ILargeOldFilesService, LargeOldFilesService>();
        services.AddSingleton<IDuplicateFinderService, DuplicateFinderService>();
        services.AddSingleton<ISimilarPhotosService, SimilarPhotosService>();
        services.AddSingleton<IShredderService, ShredderService>();
        services.AddSingleton<IQuarantineService, QuarantineService>();
        services.AddSingleton<IMalwareHashStore, MalwareHashStore>();
        services.AddSingleton<IMalwareScanner, MalwareScanner>();
        services.AddSingleton<IRealtimeProtectionService, RealtimeProtectionService>();
        services.AddSingleton<IMyToolsService, MyToolsService>();
        services.AddSingleton<IScrollDenoiserService, ScrollDenoiserService>();

        return services;
    }
}
