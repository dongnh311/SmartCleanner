using MacCleaner.Win.App.Services;
using MacCleaner.Win.Core.Alerts;
using Microsoft.Extensions.DependencyInjection;

namespace MacCleaner.Win.App;

/// <summary>
/// App-layer DI extensions for services that depend on WindowsAppSDK
/// types (toast notifications, etc.) and therefore can't live in Core
/// without dragging the SDK reference into the class library.
/// </summary>
public static class AppServices
{
    public static IServiceCollection AddAppServices(this IServiceCollection services)
    {
        services.AddSingleton<IToastService, ToastService>();
        return services;
    }
}
