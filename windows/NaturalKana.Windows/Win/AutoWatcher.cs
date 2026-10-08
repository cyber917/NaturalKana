using NaturalKana.Windows.Core;

namespace NaturalKana.Windows.Win;

/// Auto mode: polls the focused field and raises Ready once the text has been unchanged
/// for the configured pause. No keyboard hook is installed; nothing is read while paused.
public sealed class AutoWatcher : IDisposable
{
    readonly Func<AppSettings> settings;
    readonly Func<bool> paused;
    readonly CancellationTokenSource stop = new();
    FieldSnapshot? last;
    DateTime lastChange;
    string? handled; // element + text already requested, dismissed or just accepted

    /// Raised on a background thread with a stable draft at the end of its paragraph.
    public event Action<FieldSnapshot>? Ready;
    /// Raised on a background thread when the focused text changes or focus leaves the field.
    public event Action? Changed;

    public AutoWatcher(Func<AppSettings> settings, Func<bool> paused)
    {
        this.settings = settings;
        this.paused = paused;
        new Thread(Loop) { IsBackground = true, Name = "NaturalKana auto mode" }.Start();
    }

    /// Do not suggest again for this exact text (dismissed, or the accepted suggestion itself).
    public void Suppress(FieldSnapshot snapshot, string? text = null) => handled = snapshot.ElementId + "\n" + (text ?? snapshot.Text);

    void Loop()
    {
        while (!stop.IsCancellationRequested)
        {
            Thread.Sleep(300);
            var config = settings();
            if (!config.AutoMode || !config.Consent || paused()) { last = null; continue; }
            var snapshot = FieldReader.Read();
            if (snapshot is null || last is null || snapshot.ElementId != last.ElementId || snapshot.Text != last.Text)
            {
                if (last is not null) Changed?.Invoke();
                last = snapshot;
                lastChange = DateTime.UtcNow;
                continue;
            }
            if ((DateTime.UtcNow - lastChange).TotalMilliseconds < Math.Max(300, config.AutoPauseMilliseconds)) continue;
            var key = snapshot.ElementId + "\n" + snapshot.Text;
            if (key == handled || !Eligible(snapshot, config)) continue;
            handled = key;
            Ready?.Invoke(snapshot);
        }
    }

    internal static bool Eligible(FieldSnapshot snapshot, AppSettings config)
    {
        var text = snapshot.Before.Trim();
        if (snapshot.After.Trim().Length > 0 || JapaneseText.Length(text) < Math.Max(1, config.MinimumLength) || text.Length > 200) return false;
        var language = (config.ResolvingLanguage(text) ?? config).Language;
        // Unfinished romaji or pinyin (e.g. "今日はh", "我想去b") means the IME is still composing.
        if (language.Pack.RomanizedInput == true && text[^1] is >= 'a' and <= 'z' or >= 'A' and <= 'Z') return false;
        return Languages.AcceptsDraft(language, text);
    }

    public void Dispose() => stop.Cancel();
}
