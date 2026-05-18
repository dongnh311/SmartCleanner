using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using WinRT;

namespace MacCleaner.Win.App;

/// <summary>
/// Explicit entry point — WinUI 3 unpackaged apps must call
/// <c>XamlCheckProcessRequirements</c> and bootstrap the dispatcher queue
/// themselves before <c>Application.Start</c>.
/// </summary>
public static class Program
{
    [System.STAThread]
    public static void Main(string[] args)
    {
        ComWrappersSupport.InitializeComWrappers();
        Application.Start(p =>
        {
            var context = new DispatcherQueueSynchronizationContext(
                DispatcherQueue.GetForCurrentThread());
            System.Threading.SynchronizationContext.SetSynchronizationContext(context);
            _ = new App();
        });
    }
}
