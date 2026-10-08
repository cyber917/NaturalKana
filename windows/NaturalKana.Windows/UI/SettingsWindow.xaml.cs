using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Microsoft.Win32;
using NaturalKana.Windows.Core;

namespace NaturalKana.Windows.UI;

public partial class SettingsWindow : Window
{
    readonly AppSettings settings;
    readonly Func<string, bool> registerHotkey;
    readonly Action<bool> suspendHotkey;
    string hotkey;
    readonly Dictionary<ProviderKind, ProviderConfig> edits = new();
    readonly Dictionary<ProviderKind, string> pendingKeys = new();
    ProviderKind current;
    bool loading = true; // suppresses SelectionChanged while the form is being filled

    public SettingsWindow(AppSettings settings, Func<string, bool> registerHotkey, Action<bool> suspendHotkey)
    {
        InitializeComponent();
        MaxHeight = SystemParameters.WorkArea.Height - 40;
        this.settings = settings;
        this.registerHotkey = registerHotkey;
        this.suspendHotkey = suspendHotkey;
        // Older builds allowed everyday shortcuts such as Ctrl+Z; fall back to the default for those.
        hotkey = Win.HotkeyHost.CommonShortcutName(settings.Hotkey) is null ? settings.Hotkey : HotkeyPreset.Default;
        foreach (var (kind, config) in settings.ProviderConfigs) edits[kind] = config.Clone();

        Intro.Text = $"在任何软件里选中一句话（或把光标放在句尾），按 {settings.Hotkey} 获取更自然的说法。";
        Fill(ProviderBox, Enum.GetValues<ProviderKind>().Select(k => (k, Providers.Title(k))), settings.Provider);
        Fill(LanguageBox, [(SuggestionLanguage.Japanese, "日语"), (SuggestionLanguage.English, "英语")], settings.Language);
        Fill(RegisterBox, [(RegisterPreference.Both, "口语和敬语都要"), (RegisterPreference.FriendsCasual, "只要口语"), (RegisterPreference.PoliteCasual, "只要敬语")], settings.RegisterPreference);
        Fill(SlangBox, [(SlangLevel.Off, "不用"), (SlangLevel.Light, "轻度（只用常见说法）"), (SlangLevel.Trendy, "流行")], settings.SlangLevel);
        Fill(DialectBox, [(Dialect.Off, "不用"), (Dialect.Kansai, "関西弁（另给一组关西话说法，仅日语）")], settings.Dialect);
        Fill(CountBox, Enumerable.Range(1, 10).Select(n => (n, n.ToString())), settings.SuggestionLimit);
        HotkeyBox.Text = hotkey;
        HotkeyBox.GotKeyboardFocus += (_, _) => { suspendHotkey(true); HotkeyHint.Text = "请按下组合键（需含 Ctrl / Alt / Win）"; };
        HotkeyBox.LostKeyboardFocus += (_, _) => { suspendHotkey(false); HotkeyHint.Text = "点一下，再按新的组合键"; };
        HotkeyBox.PreviewKeyDown += OnRecordHotkey;
        Closed += (_, _) => suspendHotkey(false);
        Fill(ScopeBox, [(NoSelectionScope.WholeField, "检查整个输入框"), (NoSelectionScope.CurrentLine, "只检查光标前的这一行")], settings.NoSelection);
        AutoBox.IsChecked = settings.AutoMode;
        Fill(PauseBox, new[] { 500, 800, 1200, 2000 }.Select(ms => (ms, $"{ms / 1000.0:0.#} 秒")), new[] { 500, 800, 1200, 2000 }.Contains(settings.AutoPauseMilliseconds) ? settings.AutoPauseMilliseconds : 800);
        HighlightBox.IsChecked = settings.HighlightChanges;
        CapBox.Text = settings.DailyCap.ToString();
        ConsentBox.IsChecked = settings.Consent;
        StartupBox.IsChecked = Startup.Enabled;
        Fill(ProtocolBox, [(ProviderProtocol.ChatCompletions, "OpenAI Chat Completions"), (ProviderProtocol.AnthropicMessages, "Claude Messages")], ProviderProtocol.ChatCompletions);
        Fill(ResponseBox, [(JsonResponseMode.Automatic, "自动"), (JsonResponseMode.Schema, "JSON Schema"), (JsonResponseMode.Object, "JSON Object"), (JsonResponseMode.Prompt, "仅提示词")], JsonResponseMode.Automatic);
        Fill(TokenBox, [(TokenParameter.Automatic, "自动"), (TokenParameter.MaxTokens, "max_tokens"), (TokenParameter.MaxCompletionTokens, "max_completion_tokens")], TokenParameter.Automatic);
        current = settings.Provider;
        LoadProvider(current);
    }

    static void Fill<T>(ComboBox box, IEnumerable<(T value, string title)> items, T selected)
    {
        box.Items.Clear();
        foreach (var (value, title) in items)
        {
            var item = new ComboBoxItem { Content = title, Tag = value };
            box.Items.Add(item);
            if (EqualityComparer<T>.Default.Equals(value, selected)) box.SelectedItem = item;
        }
        box.SelectedIndex = Math.Max(0, box.SelectedIndex);
    }

    static T Get<T>(ComboBox box) => (T)((ComboBoxItem)box.SelectedItem).Tag;

    void OnRecordHotkey(object sender, System.Windows.Input.KeyEventArgs e)
    {
        e.Handled = true;
        var key = e.Key == System.Windows.Input.Key.System ? e.SystemKey : e.Key;
        if (key == System.Windows.Input.Key.Escape) { Keyboard.ClearFocus(); return; }
        if (Win.HotkeyHost.Format(Keyboard.Modifiers, key) is { } text)
        {
            if (Win.HotkeyHost.CommonShortcutName(text) is { } name)
            {
                HotkeyHint.Text = $"{text} 是常用的“{name}”，会让其他软件里的{name}失效，请换一个";
                return;
            }
            hotkey = text;
            HotkeyBox.Text = text;
            HotkeyHint.Text = "已录制，点“保存”生效";
            Keyboard.ClearFocus();
        }
    }

    ProviderConfig Edit(ProviderKind kind) => edits.TryGetValue(kind, out var c) ? c : edits[kind] = Providers.Default(kind);

    void LoadProvider(ProviderKind kind)
    {
        loading = true;
        var config = Edit(kind);
        UrlBox.Text = config.BaseUrl;
        ModelBox.Text = config.Model;
        KeyBox.Password = pendingKeys.GetValueOrDefault(kind, "");
        KeyState.Text = SecretStore.Has(kind) ? "已保存" : "未保存";
        ThinkingBox.IsChecked = config.DisableThinking;
        var qwen = Providers.IsQwen(kind);
        ThinkingRow.Visibility = ThinkingDivider.Visibility = qwen ? Visibility.Visible : Visibility.Collapsed;
        Select(ProtocolBox, config.Protocol);
        Select(ResponseBox, config.ResponseMode);
        Select(TokenBox, config.TokenParameter);
        loading = false;
    }

    static void Select<T>(ComboBox box, T value) =>
        box.SelectedItem = box.Items.OfType<ComboBoxItem>().First(i => EqualityComparer<T>.Default.Equals((T)i.Tag, value));

    void StoreProvider(ProviderKind kind)
    {
        var config = Edit(kind);
        config.BaseUrl = UrlBox.Text.Trim();
        config.Model = ModelBox.Text.Trim();
        config.DisableThinking = ThinkingBox.IsChecked == true;
        config.Protocol = Get<ProviderProtocol>(ProtocolBox);
        config.ResponseMode = Get<JsonResponseMode>(ResponseBox);
        config.TokenParameter = Get<TokenParameter>(TokenBox);
        if (KeyBox.Password.Trim().Length > 0) pendingKeys[kind] = KeyBox.Password.Trim();
    }

    void OnProviderChanged(object sender, SelectionChangedEventArgs e)
    {
        if (loading || ProviderBox.SelectedItem is null) return;
        StoreProvider(current);
        current = Get<ProviderKind>(ProviderBox);
        LoadProvider(current);
    }

    void OnResetUrl(object sender, RoutedEventArgs e) => UrlBox.Text = Providers.Default(current).BaseUrl;

    void OnDeleteKey(object sender, RoutedEventArgs e)
    {
        SecretStore.Delete(current);
        pendingKeys.Remove(current);
        KeyBox.Password = "";
        KeyState.Text = "未保存";
        Show("已删除当前服务商的密钥。", false);
    }

    void Show(string message, bool warning) { Result.Text = message; Result.Foreground = warning ? Theme.Warning : Theme.Gray; }

    async void OnTest(object sender, RoutedEventArgs e)
    {
        StoreProvider(current);
        var key = pendingKeys.GetValueOrDefault(current) ?? SecretStore.Read(current) ?? "";
        var trial = new AppSettings
        {
            Language = Get<SuggestionLanguage>(LanguageBox),
            RegisterPreference = Get<RegisterPreference>(RegisterBox),
            SlangLevel = Get<SlangLevel>(SlangBox),
            Dialect = Get<Dialect>(DialectBox),
            MaximumSuggestions = Get<int>(CountBox),
        };
        TestButton.IsEnabled = false;
        Show("正在发送一条固定例句测试…（可能产生少量费用）", false);
        var watch = Stopwatch.StartNew();
        try
        {
            var json = await new Provider(current, Edit(current), key).SuggestAsync(PromptBuilder.Make(Languages.TestDraft(trial.Language), trial), CancellationToken.None);
            var report = ResponseValidator.Inspect(json, Languages.TestDraft(trial.Language), trial);
            var seconds = watch.Elapsed.TotalSeconds.ToString("0.0");
            Show(report.Suggestions.Count > 0
                ? $"连接成功：返回 {report.Suggestions.Count} 条建议，用时 {seconds} 秒。例：{report.Suggestions[0].Text}"
                : $"连接成功（用时 {seconds} 秒）：{report.EmptyMessage}", false);
        }
        catch (SuggestionException ex) { Show(ex.Message, true); }
        finally { TestButton.IsEnabled = true; }
    }

    void OnSave(object sender, RoutedEventArgs e)
    {
        StoreProvider(current);
        if (!int.TryParse(CapBox.Text.Trim(), out var cap) || cap < 0) { Show("每日请求上限请填写 0 或正整数。", true); return; }
        if (!registerHotkey(hotkey)) { Show($"快捷键 {hotkey} 已被其他软件占用，请换一个。", true); return; }
        try
        {
            foreach (var (kind, key) in pendingKeys) SecretStore.Write(kind, key);
        }
        catch (InvalidOperationException ex) { Show(ex.Message, true); return; }
        pendingKeys.Clear();

        settings.Provider = current;
        settings.ProviderConfigs = edits.ToDictionary(p => p.Key, p => p.Value.Clone());
        settings.Language = Get<SuggestionLanguage>(LanguageBox);
        settings.RegisterPreference = Get<RegisterPreference>(RegisterBox);
        settings.SlangLevel = Get<SlangLevel>(SlangBox);
        settings.Dialect = Get<Dialect>(DialectBox);
        settings.MaximumSuggestions = Get<int>(CountBox);
        settings.HighlightChanges = HighlightBox.IsChecked == true;
        settings.Hotkey = hotkey;
        settings.NoSelection = Get<NoSelectionScope>(ScopeBox);
        settings.AutoMode = AutoBox.IsChecked == true;
        settings.AutoPauseMilliseconds = Get<int>(PauseBox);
        settings.DailyCap = cap;
        settings.Consent = ConsentBox.IsChecked == true;
        settings.Save();
        Startup.Enabled = StartupBox.IsChecked == true;
        Close();
    }
}

static class Startup
{
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    public static bool Enabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue("NaturalKana") is string;
        }
        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey);
            if (value && Environment.ProcessPath is { } path) key.SetValue("NaturalKana", $"\"{path}\"");
            else key.DeleteValue("NaturalKana", false);
        }
    }
}
