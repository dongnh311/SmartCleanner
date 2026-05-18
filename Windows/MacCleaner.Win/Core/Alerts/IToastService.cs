namespace MacCleaner.Win.Core.Alerts;

public interface IToastService
{
    /// <summary>Fire a toast with a title + body.
    /// No-op if the host does not have notification permission.</summary>
    void Notify(string title, string body);
}
