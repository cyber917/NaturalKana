using System.Drawing;
using System.Windows;
using NaturalKana.Windows.Core;
using NaturalKana.Windows.UI;
using NaturalKana.Windows.Win;
using Forms = System.Windows.Forms;

namespace NaturalKana.Windows;

/// Tray app.
/// Hotkey: copy the selection (or the input box / current line) → ask the provider → card → paste.
/// Auto mode: read the focused field after a pause → passive card → Ctrl+number replaces the paragraph.
public partial class App : Application
{
    const int MainHotkey = 1;
    Mutex? single;
    bool ownsMutex;
    Forms.NotifyIcon? tray;
    HotkeyHost? hotkeys;
    AutoWatcher? watcher;
    AppSettings settings = new();
    SettingsWindow? settingsWindow;
    CancellationTokenSource? request;
    SuggestionWindow? autoCard;
    IDisposable? autoKeys;
    volatile bool busy;
    readonly Dictionary<string, ValidationReport> cache = new();

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        single = new Mutex(true, @"Local\NaturalKana.Windows", out ownsMutex);
        if (!ownsMutex) { MessageBox.Show("NaturalKana 已经在运行，请在任务栏右下角的托盘里找到它。", "NaturalKana"); Shutdown(); return; }

        settings = AppSettings.Load();
        hotkeys = new HotkeyHost();
        var registered = RegisterMainHotkey(settings.Hotkey);

        tray = new Forms.NotifyIcon { Icon = MakeIcon(), Text = "NaturalKana", Visible = true };
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("设置…", null, (_, _) => OpenSettings());
        menu.Items.Add("使用说明", null, (_, _) => Open("https://github.com/cyber917/NaturalKana/blob/main/docs/WINDOWS.md"));
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("退出", null, (_, _) => Quit());
        tray.ContextMenuStrip = menu;
        tray.DoubleClick += (_, _) => OpenSettings();

        watcher = new AutoWatcher(() => settings, () => busy || settingsWindow is not null);
        watcher.Ready += snapshot => Dispatcher.BeginInvoke(() => _ = AutoSuggestAsync(snapshot));
        // Typing again (or leaving the field) cancels a pending auto request and closes its card.
        watcher.Changed += () => Dispatcher.BeginInvoke(() =>
        {
            if (autoCard is null) return;
            request?.Cancel();
            autoCard.Dismiss(refocus: false);
        });

        if (!registered)
            tray.ShowBalloonTip(5000, "NaturalKana", $"快捷键 {settings.Hotkey} 被其他软件占用了，请在设置里换一个。", Forms.ToolTipIcon.Warning);
        if (!settings.Consent || !SecretStore.Has(settings.Provider)) OpenSettings();
        else tray.ShowBalloonTip(4000, "NaturalKana 已在后台运行", $"选中一句{Languages.Title(settings.Language)}，或直接按 {settings.Hotkey}", Forms.ToolTipIcon.None);
    }

    bool RegisterMainHotkey(string keys) => hotkeys!.Register(MainHotkey, keys, OnHotkey);

    static void Open(string url) =>
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true });

    void OpenSettings()
    {
        if (settingsWindow is { IsLoaded: true }) { settingsWindow.Activate(); return; }
        autoCard?.Dismiss(refocus: false);
        settingsWindow = new SettingsWindow(settings, RegisterMainHotkey, suspend =>
        {
            if (suspend) hotkeys!.Unregister(MainHotkey);
            else RegisterMainHotkey(settings.Hotkey);
        });
        settingsWindow.Closed += (_, _) =>
        {
            settingsWindow = null;
            cache.Clear();
            // Saving may have changed the hotkey; closing without saving keeps the old one.
            RegisterMainHotkey(settings.Hotkey);
        };
        settingsWindow.Show();
        settingsWindow.Activate();
    }

    bool Ready()
    {
        if (settings.Consent && SecretStore.Has(settings.Provider)) return true;
        OpenSettings();
        return false;
    }

    // ---------- hotkey ----------

    async void OnHotkey()
    {
        if (busy) return;
        busy = true;
        autoCard?.Dismiss(refocus: false);
        try { if (Ready()) await HotkeyAsync(); }
        finally { busy = false; }
    }

    async Task HotkeyAsync()
    {
        var capture = await TextBridge.CaptureAsync(settings.NoSelection);
        if (capture is null)
        {
            tray?.ShowBalloonTip(3000, "NaturalKana", "没有取到文字：请把光标放进输入框，或先选中一句话再按快捷键。", Forms.ToolTipIcon.None);
            return;
        }
        var draft = capture.Text;
        var card = new SuggestionWindow(draft.Length > 200 ? draft[^200..] : draft, capture.Anchor, settings.HighlightChanges, settings.Language, passive: false);
        string? chosen = null;
        var refocus = false;
        var closed = new TaskCompletionSource();
        card.Finished += (text, back) => { chosen = text; refocus = back; closed.TrySetResult(); };
        card.ShowNearCaret();

        request?.Cancel();
        request = new CancellationTokenSource();
        var multiline = draft.Contains('\n') || draft.Contains('\r');
        if (multiline)
            card.ShowMessage(capture.AutoSelected
                ? "输入框里有好几行，一次只能检查一句。请选中要检查的那一句再按快捷键。"
                : "一次只能检查一句话，请只选中一行。");
        else _ = FillAsync(card, draft, request.Token);

        await closed.Task;
        request.Cancel();
        if (chosen is not null) await TextBridge.PasteAsync(capture.Window, chosen);
        else if (refocus) await TextBridge.RefocusAsync(capture.Window, collapseSelection: capture.AutoSelected);
    }

    // ---------- auto mode ----------

    async Task AutoSuggestAsync(FieldSnapshot snapshot)
    {
        if (busy || settingsWindow is not null || !settings.AutoMode || !settings.Consent || !SecretStore.Has(settings.Provider)) return;
        autoCard?.Dismiss(refocus: false);
        var draft = snapshot.Before.Trim();
        var card = new SuggestionWindow(draft, snapshot.Anchor, settings.HighlightChanges, settings.Language, passive: true);
        autoCard = card;
        string? chosen = null;
        var closed = new TaskCompletionSource();
        card.Finished += (text, _) => { chosen = text; closed.TrySetResult(); };

        request?.Cancel();
        request = new CancellationTokenSource();
        var token = request.Token;
        // Show the card only once there is something worth showing, so typing is never interrupted by a spinner.
        var report = await RequestAsync(draft, token, card);
        if (token.IsCancellationRequested || autoCard != card || card.IsFinished || report is null || report.Suggestions.Count == 0)
        {
            card.Dismiss(refocus: false);
            if (autoCard == card) autoCard = null;
            return;
        }
        card.ShowSuggestions(report.Suggestions);
        card.ShowNearCaret();
        autoKeys = hotkeys!.RegisterTemporary(
            Enumerable.Range(1, 9).Select(n => ($"Ctrl+D{n}", (Action)(() => card.Accept(n - 1))))
                .Append(("Escape", () => card.Dismiss(refocus: false))));

        await closed.Task;
        autoKeys.Dispose();
        autoKeys = null;
        if (autoCard == card) autoCard = null;
        if (chosen is null) { watcher!.Suppress(snapshot); return; }

        watcher!.Suppress(snapshot, chosen);
        busy = true;
        try
        {
            if (await Task.Run(() => FieldReader.SelectForReplace(snapshot))) await TextBridge.PasteAsync(IntPtr.Zero, chosen);
            else
            {
                TextBridge.Copy(chosen);
                tray?.ShowBalloonTip(3000, "NaturalKana", "原句已经变了或无法自动替换，建议已复制，请手动粘贴。", Forms.ToolTipIcon.None);
            }
        }
        finally { busy = false; }
    }

    // ---------- shared ----------

    async Task FillAsync(SuggestionWindow card, string draft, CancellationToken cancel)
    {
        if (JapaneseText.Length(draft) < 2) { card.ShowMessage("句子太短了。"); return; }
        if (!Languages.AcceptsDraft(settings.Language, draft)) { card.ShowMessage(Languages.NotThisLanguage(settings.Language)); return; }
        var report = await RequestAsync(draft, cancel, card);
        if (report is null || cancel.IsCancellationRequested) return;
        if (report.Suggestions.Count > 0) card.ShowSuggestions(report.Suggestions);
        else card.ShowMessage(report.EmptyMessage!);
    }

    /// Cached per draft and settings. Errors are shown on the card; returns null on error or cancel.
    async Task<ValidationReport?> RequestAsync(string draft, CancellationToken cancel, SuggestionWindow card)
    {
        var config = settings.Config(settings.Provider);
        var key = string.Join("\u0001", draft, settings.Language, settings.Provider, config.BaseUrl, config.Model,
            settings.RegisterPreference, settings.SlangLevel, settings.SuggestionLimit);
        if (cache.TryGetValue(key, out var cached)) return cached;
        try
        {
            if (!settings.ReserveRequest()) throw new SuggestionException(Diagnostic.Quota);
            var provider = new Provider(settings.Provider, config, SecretStore.Read(settings.Provider) ?? "");
#if DEBUG
            // UI test hook (Debug builds only): replay a canned provider reply from a file.
            var json = Environment.GetEnvironmentVariable("NATURALKANA_FAKE_REPLY") is { Length: > 0 } fake
                ? await Task.Delay(400, cancel).ContinueWith(_ => System.IO.File.ReadAllText(fake), cancel)
                : await provider.SuggestAsync(PromptBuilder.Make(draft, settings), cancel);
#else
            var json = await provider.SuggestAsync(PromptBuilder.Make(draft, settings), cancel);
#endif
            if (cancel.IsCancellationRequested) return null;
            var report = ResponseValidator.Inspect(json, draft, settings);
            // Only explicit "natural" results and real suggestions are reused; unknown empty replies are retried.
            if (report.Suggestions.Count > 0 || report.Assessment == Assessment.Natural)
            {
                if (cache.Count > 64) cache.Clear();
                cache[key] = report;
            }
            return report;
        }
        catch (OperationCanceledException) { return null; }
        catch (SuggestionException ex)
        {
            if (!cancel.IsCancellationRequested) card.ShowMessage(ex.Message, true);
            return null;
        }
    }

    /// Tray icon drawn at runtime: a black rounded square with "あ".
    static Icon MakeIcon()
    {
        using var bitmap = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bitmap))
        {
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            using var path = new System.Drawing.Drawing2D.GraphicsPath();
            path.AddArc(1, 1, 12, 12, 180, 90); path.AddArc(19, 1, 12, 12, 270, 90);
            path.AddArc(19, 19, 12, 12, 0, 90); path.AddArc(1, 19, 12, 12, 90, 90);
            path.CloseFigure();
            g.FillPath(new SolidBrush(System.Drawing.Color.FromArgb(29, 29, 31)), path);
            using var font = new Font("Yu Gothic UI", 15, System.Drawing.FontStyle.Bold, GraphicsUnit.Pixel);
            var size = g.MeasureString("あ", font);
            g.DrawString("あ", font, Brushes.White, (32 - size.Width) / 2 + 1, (32 - size.Height) / 2 + 1);
        }
        return Icon.FromHandle(bitmap.GetHicon());
    }

    void Quit()
    {
        request?.Cancel();
        watcher?.Dispose();
        autoKeys?.Dispose();
        hotkeys?.Dispose();
        if (tray is not null) { tray.Visible = false; tray.Dispose(); }
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        if (ownsMutex) single?.ReleaseMutex();
        base.OnExit(e);
    }
}
