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
    readonly Func<string, string, string?> registerHotkeys;
    readonly Action<bool> suspendHotkey;
    string hotkey, selectAllHotkey;
    readonly Dictionary<ProviderKind, ProviderConfig> edits = new();
    readonly Dictionary<ProviderKind, string> pendingKeys = new();
    ProviderKind current;
    bool loading = true; // suppresses SelectionChanged while the form is being filled
    bool filling; // suppresses language SelectionChanged while the choices are (re)filled

    public SettingsWindow(AppSettings settings, Func<string, string, string?> registerHotkeys, Action<bool> suspendHotkey)
    {
        InitializeComponent();
        // Translate the XAML text before any code sets dynamic text.
        Localizer.Apply(this);
        MaxHeight = SystemParameters.WorkArea.Height - 40;
        this.settings = settings;
        this.registerHotkeys = registerHotkeys;
        this.suspendHotkey = suspendHotkey;
        // Older builds allowed everyday shortcuts such as Ctrl+Z; fall back to the default for those.
        (hotkey, selectAllHotkey) = Win.HotkeyHost.SavedShortcuts(settings.Hotkey, settings.SelectAllHotkey);
        foreach (var (kind, config) in settings.ProviderConfigs) edits[kind] = config.Clone();

        UIText.Language = settings.Interface;
        FillChoices();
        Fill(CountBox, Enumerable.Range(1, 10).Select(n => (n, n.ToString())), settings.SuggestionLimit);
        HotkeyBox.Text = hotkey;
        SelectAllHotkeyBox.Text = selectAllHotkey;
        SetupRecorder(HotkeyBox, HotkeyHint);
        SetupRecorder(SelectAllHotkeyBox, SelectAllHotkeyHint);
        Closed += (_, _) => suspendHotkey(false);
        AutoBox.IsChecked = settings.AutoMode;
        HighlightBox.IsChecked = settings.HighlightChanges;
        CapBox.Text = settings.DailyCap.ToString();
        ConsentBox.IsChecked = settings.Consent;
        StartupBox.IsChecked = Startup.Enabled;
        Fill(ProtocolBox, [(ProviderProtocol.ChatCompletions, "OpenAI Chat Completions"), (ProviderProtocol.AnthropicMessages, "Claude Messages")], ProviderProtocol.ChatCompletions);
        current = settings.Provider;
        LoadProvider(current);
    }

    /// Fills every translated choice, keeping the current selections (or the saved settings on first fill).
    void FillChoices()
    {
        filling = true;
        Intro.Text = UIText.T("在任何软件里选中一句话（或把光标放在句尾），按 %@ 获取更自然的说法。", $"{settings.Hotkey}");
        Fill(InterfaceBox, Enum.GetValues<InterfaceLanguage>().Select(l => (l, UIText.Title(l))), Pick(InterfaceBox, settings.Interface));
        Fill(ProviderBox, Enum.GetValues<ProviderKind>().Select(k => (k, Providers.Title(k))), Pick(ProviderBox, settings.Provider));
        // null = automatic: detect each sentence; PrimaryBox then holds the language for ambiguous sentences.
        Fill(LanguageBox, Languages.All.Select(l => ((SuggestionLanguage?)l, Languages.Title(l))).Prepend(((SuggestionLanguage?)null, UIText.T("自动"))),
            Pick(LanguageBox, settings.AutoLanguage ? null : (SuggestionLanguage?)settings.Language));
        Fill(PrimaryBox, Languages.All.Select(l => (l, Languages.Title(l))), Pick(PrimaryBox, settings.Language));
        PrimaryRow.Visibility = Get<SuggestionLanguage?>(LanguageBox) is null ? Visibility.Visible : Visibility.Collapsed;
        Fill(RegisterBox, [(RegisterPreference.Both, UIText.T("口语和敬语都要")), (RegisterPreference.FriendsCasual, UIText.T("只要口语")), (RegisterPreference.PoliteCasual, UIText.T("只要敬语"))], Pick(RegisterBox, settings.RegisterPreference));
        Fill(SlangBox, [(SlangLevel.Off, UIText.T("不用")), (SlangLevel.Light, UIText.T("轻度（只用常见说法）")), (SlangLevel.Trendy, UIText.T("流行"))], Pick(SlangBox, settings.SlangLevel));
        Fill(DialectBox, [(Dialect.Off, UIText.T("不用")), (Dialect.Kansai, UIText.T("関西弁（另给一组关西话说法，仅日语）"))], Pick(DialectBox, settings.Dialect));
        Fill(ScopeBox, [(NoSelectionScope.WholeField, UIText.T("检查整个输入框")), (NoSelectionScope.CurrentLine, UIText.T("只检查光标前的这一行"))], Pick(ScopeBox, settings.NoSelection));
        var pauses = new[] { 500, 800, 1200, 2000 };
        Fill(PauseBox, pauses.Select(ms => (ms, UIText.T("%@ 秒", $"{ms / 1000.0:0.#}"))), Pick(PauseBox, pauses.Contains(settings.AutoPauseMilliseconds) ? settings.AutoPauseMilliseconds : 800));
        Fill(ResponseBox, [(JsonResponseMode.Automatic, UIText.T("自动")), (JsonResponseMode.Schema, "JSON Schema"), (JsonResponseMode.Object, "JSON Object"), (JsonResponseMode.Prompt, UIText.T("仅提示词"))], Pick(ResponseBox, JsonResponseMode.Automatic));
        Fill(TokenBox, [(TokenParameter.Automatic, UIText.T("自动")), (TokenParameter.MaxTokens, "max_tokens"), (TokenParameter.MaxCompletionTokens, "max_completion_tokens")], Pick(TokenBox, TokenParameter.Automatic));
        var disabled = SuggestionLanguages.Children.Count == 0 ? settings.DisabledSuggestionLanguages
            : SuggestionLanguages.Children.OfType<CheckBox>().Where(c => c.IsChecked != true).Select(c => (SuggestionLanguage)c.Tag).ToList();
        SuggestionLanguages.Children.Clear();
        foreach (var language in Languages.All)
            SuggestionLanguages.Children.Add(new CheckBox { Content = Languages.Title(language), Tag = language,
                IsChecked = !disabled.Contains(language), Margin = new Thickness(0, 4, 0, 4) });
        filling = false;
    }

    static T Pick<T>(ComboBox box, T fallback) => box.SelectedItem is ComboBoxItem item ? (T)item.Tag! : fallback;

    void OnInterfaceChanged(object sender, SelectionChangedEventArgs e)
    {
        if (filling || InterfaceBox.SelectedItem is null) return;
        // Preview immediately; it is kept only when the user saves.
        UIText.Language = Get<InterfaceLanguage>(InterfaceBox);
        Localizer.Apply(this, capture: false);
        loading = true; // refilling the provider list must not reload the provider fields
        FillChoices();
        loading = false;
        KeyState.Text = SecretStore.Has(current) ? UIText.T("已保存") : UIText.T("未保存");
    }

    void OnLanguageChanged(object sender, SelectionChangedEventArgs e)
    {
        if (filling || LanguageBox.SelectedItem is null) return;
        PrimaryRow.Visibility = Get<SuggestionLanguage?>(LanguageBox) is null ? Visibility.Visible : Visibility.Collapsed;
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

    void SetupRecorder(TextBox box, TextBlock hint)
    {
        box.GotKeyboardFocus += (_, _) => { suspendHotkey(true); hint.Text = UIText.T("请按下组合键（需含 Ctrl / Alt / Win）"); };
        box.LostKeyboardFocus += (_, _) => { suspendHotkey(false); hint.Text = UIText.T("点一下，再按新的组合键"); };
        box.PreviewKeyDown += (_, e) =>
        {
            e.Handled = true;
            var key = e.Key == Key.System ? e.SystemKey : e.Key;
            if (key == Key.Escape) { Keyboard.ClearFocus(); return; }
            if (Win.HotkeyHost.Format(Keyboard.Modifiers, key) is not { } text) return;
            if (Win.HotkeyHost.CommonShortcutName(text) is { } name)
            {
                hint.Text = UIText.T("%@ 是常用的“%@”，会让其他软件里的%@失效，请换一个", text, name, name);
                return;
            }
            if (box == HotkeyBox) hotkey = text;
            else selectAllHotkey = text;
            box.Text = text;
            Keyboard.ClearFocus();
            hint.Text = UIText.T("已录制，点“保存”生效");
        };
    }

    ProviderConfig Edit(ProviderKind kind) => edits.TryGetValue(kind, out var c) ? c : edits[kind] = Providers.Default(kind);

    void LoadProvider(ProviderKind kind)
    {
        loading = true;
        var config = Edit(kind);
        UrlBox.Text = config.BaseUrl;
        ModelBox.Text = config.Model;
        KeyBox.Password = pendingKeys.GetValueOrDefault(kind, "");
        KeyState.Text = SecretStore.Has(kind) ? UIText.T("已保存") : UIText.T("未保存");
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
        KeyState.Text = UIText.T("未保存");
        Show(UIText.T("已删除当前服务商的密钥。"), false);
    }

    void Show(string message, bool warning) { Result.Text = message; Result.Foreground = warning ? Theme.Warning : Theme.Gray; }

    async void OnTest(object sender, RoutedEventArgs e)
    {
        StoreProvider(current);
        var key = pendingKeys.GetValueOrDefault(current) ?? SecretStore.Read(current) ?? "";
        var trial = new AppSettings
        {
            Language = Get<SuggestionLanguage?>(LanguageBox) ?? Get<SuggestionLanguage>(PrimaryBox),
            RegisterPreference = Get<RegisterPreference>(RegisterBox),
            SlangLevel = Get<SlangLevel>(SlangBox),
            Dialect = Get<Dialect>(DialectBox),
            MaximumSuggestions = Get<int>(CountBox),
        };
        TestButton.IsEnabled = false;
        Show(UIText.T("正在发送一条固定例句测试…（可能产生少量费用）"), false);
        var watch = Stopwatch.StartNew();
        try
        {
            var json = await new Provider(current, Edit(current), key).SuggestAsync(PromptBuilder.Make(Languages.TestDraft(trial.Language), trial), CancellationToken.None);
            var report = ResponseValidator.Inspect(json, Languages.TestDraft(trial.Language), trial);
            var seconds = watch.Elapsed.TotalSeconds.ToString("0.0");
            Show(report.Suggestions.Count > 0
                ? UIText.T("连接成功：返回 %@ 条建议，用时 %@ 秒。例：%@", $"{report.Suggestions.Count}", $"{seconds}", $"{report.Suggestions[0].Text}")
                : UIText.T("连接成功（用时 %@ 秒）：%@", $"{seconds}", $"{report.EmptyMessage}"), false);
        }
        catch (SuggestionException ex) { Show(ex.Message, true); }
        finally { TestButton.IsEnabled = true; }
    }

    void OnSave(object sender, RoutedEventArgs e)
    {
        StoreProvider(current);
        if (!int.TryParse(CapBox.Text.Trim(), out var cap) || cap < 0) { Show(UIText.T("每日请求上限请填写 0 或正整数。"), true); return; }
        if (Win.HotkeyHost.SameCombination(hotkey, selectAllHotkey)) { Show(UIText.T("两个快捷键不能相同。"), true); return; }
        if (registerHotkeys(hotkey, selectAllHotkey) is { } failed) { Show(UIText.T("快捷键 %@ 已被其他软件占用，请换一个。", failed), true); return; }
        try
        {
            foreach (var (kind, key) in pendingKeys) SecretStore.Write(kind, key);
        }
        catch (InvalidOperationException ex) { registerHotkeys(settings.Hotkey, settings.SelectAllHotkey); Show(ex.Message, true); return; }
        pendingKeys.Clear();

        settings.Provider = current;
        settings.ProviderConfigs = edits.ToDictionary(p => p.Key, p => p.Value.Clone());
        settings.DisabledSuggestionLanguages = SuggestionLanguages.Children.OfType<CheckBox>()
            .Where(c => c.IsChecked != true).Select(c => (SuggestionLanguage)c.Tag).ToList();
        settings.AutoLanguage = Get<SuggestionLanguage?>(LanguageBox) is null;
        settings.Language = Get<SuggestionLanguage?>(LanguageBox) ?? Get<SuggestionLanguage>(PrimaryBox);
        settings.Interface = Get<InterfaceLanguage>(InterfaceBox);
        settings.RegisterPreference = Get<RegisterPreference>(RegisterBox);
        settings.SlangLevel = Get<SlangLevel>(SlangBox);
        settings.Dialect = Get<Dialect>(DialectBox);
        settings.MaximumSuggestions = Get<int>(CountBox);
        settings.HighlightChanges = HighlightBox.IsChecked == true;
        settings.Hotkey = hotkey;
        settings.SelectAllHotkey = selectAllHotkey;
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
