using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace MacCleaner.Win.Core.DI;

/// <summary>
/// Composition root for Core services. Phase 1 will register the system
/// metric / process / drive / registry / sqlite services here; for now this
/// just wires logging so the App layer can call <c>AddCoreServices</c>
/// from <c>App.xaml.cs</c> without referencing concrete types.
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
        return services;
    }
}
