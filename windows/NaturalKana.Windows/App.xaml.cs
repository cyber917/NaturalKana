using System.Drawing;
using System.Windows;
using NaturalKana.Windows.Core;
using NaturalKana.Windows.UI;
using NaturalKana.Windows.Win;
using Forms = System.Windows.Forms;

namespace NaturalKana.Windows;

/// Tray app: hotkey → copy the sentence → ask the provider → show the card → paste the choice.
public partial class App : Application
{
    Mutex? single;
    bool ownsMutex;
    Forms.NotifyIcon? tray;
    Hotkey? hotkey;
    AppSettings settings = new();
    SettingsWindow? settingsWindow;
    CancellationTokenSource? request;
    bool busy;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        single = new Mutex(true, @"Local\NaturalKana.Windows", out ownsMutex);
        if (!ownsMutex) { MessageBox.Show("NaturalKana 已经在运行，请在任务栏右下角的托盘里找到它。", "NaturalKana"); Shutdown(); return; }

        settings = AppSettings.Load();
        hotkey = new Hotkey();
        hotkey.Pressed += OnHotkey;
        var registered = hotkey.Register(settings.Hotkey);

        tray = new Forms.NotifyIcon { Icon = MakeIcon(), Text = "NaturalKana", Visible = true };
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("设置…", null, (_, _) => OpenSettings());
        menu.Items.Add("使用说明", null, (_, _) => Open("https://github.com/cyber917/NaturalKana/blob/main/docs/WINDOWS.md"));
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("退出", null, (_, _) => Quit());
        tray.ContextMenuStrip = menu;
        tray.DoubleClick += (_, _) => OpenSettings();

        if (!registered)
            tray.ShowBalloonTip(5000, "NaturalKana", $"快捷键 {settings.Hotkey} 被其他软件占用了，请在设置里换一个。", Forms.ToolTipIcon.Warning);
        if (!settings.Consent || !SecretStore.Has(settings.Provider)) OpenSettings();
        else tray.ShowBalloonTip(4000, "NaturalKana 已在后台运行", $"选中一句{Languages.Title(settings.Language)}，按 {settings.Hotkey}", Forms.ToolTipIcon.None);
    }

    static void Open(string url) =>
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true });

    void OpenSettings()
    {
        if (settingsWindow is { IsLoaded: true }) { settingsWindow.Activate(); return; }
        settingsWindow = new SettingsWindow(settings, hotkey!.Register);
        settingsWindow.Closed += (_, _) =>
        {
            settingsWindow = null;
            // Re-register in case the user picked a hotkey but closed without saving.
            if (hotkey.Registered != settings.Hotkey) hotkey.Register(settings.Hotkey);
        };
        settingsWindow.Show();
        settingsWindow.Activate();
    }

    async void OnHotkey()
    {
        if (busy) return;
        busy = true;
        try { await RunAsync(); }
        finally { busy = false; }
    }

    async Task RunAsync()
    {
        if (!settings.Consent || !SecretStore.Has(settings.Provider))
        {
            OpenSettings();
            return;
        }
        var capture = await TextBridge.CaptureAsync();
        if (capture is null)
        {
            tray?.ShowBalloonTip(3000, "NaturalKana", "没有取到文字：请先选中一句话，或把光标放在句尾再按快捷键。", Forms.ToolTipIcon.None);
            return;
        }

        var draft = capture.Text;
        var card = new SuggestionWindow(draft.Length > 200 ? draft[^200..] : draft, capture.Anchor, settings.HighlightChanges, settings.Language);
        string? chosen = null;
        var refocus = false;
        var closed = new TaskCompletionSource();
        card.Finished += (text, back) => { chosen = text; refocus = back; closed.TrySetResult(); };
        card.ShowNearCaret();

        request?.Cancel();
        request = new CancellationTokenSource();
        _ = FillAsync(card, draft, request.Token);

        await closed.Task;
        request.Cancel();
        if (chosen is not null) await TextBridge.PasteAsync(capture.Window, chosen);
        else if (refocus) TextBridge.Refocus(capture.Window);
    }

    async Task FillAsync(SuggestionWindow card, string draft, CancellationToken cancel)
    {
        try
        {
            if (draft.Contains('\n') || draft.Contains('\r')) { card.ShowMessage("一次只能检查一句话，请只选中一行。"); return; }
            if (JapaneseText.Length(draft) < 2) { card.ShowMessage("句子太短了。"); return; }
            if (!Languages.AcceptsDraft(settings.Language, draft)) { card.ShowMessage(Languages.NotThisLanguage(settings.Language)); return; }
            if (!settings.ReserveRequest()) { card.ShowMessage(SuggestionException.Describe(Diagnostic.Quota), true); return; }

            var provider = new Provider(settings.Provider, settings.Config(settings.Provider), SecretStore.Read(settings.Provider) ?? "");
#if DEBUG
            // UI test hook (Debug builds only): replay a canned provider reply from a file.
            var json = Environment.GetEnvironmentVariable("NATURALKANA_FAKE_REPLY") is { Length: > 0 } fake
                ? await Task.Delay(400, cancel).ContinueWith(_ => System.IO.File.ReadAllText(fake), cancel)
                : await provider.SuggestAsync(PromptBuilder.Make(draft, settings), cancel);
#else
            var json = await provider.SuggestAsync(PromptBuilder.Make(draft, settings), cancel);
#endif
            if (cancel.IsCancellationRequested) return;
            var report = ResponseValidator.Inspect(json, draft, settings);
            if (report.Suggestions.Count > 0) card.ShowSuggestions(report.Suggestions);
            else card.ShowMessage(report.EmptyMessage!);
        }
        catch (OperationCanceledException) { }
        catch (SuggestionException ex) { if (!cancel.IsCancellationRequested) card.ShowMessage(ex.Message, true); }
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
        hotkey?.Dispose();
        if (tray is not null) { tray.Visible = false; tray.Dispose(); }
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        if (ownsMutex) single?.ReleaseMutex();
        base.OnExit(e);
    }
}
