using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace NaturalKana.Windows.Core;

public enum ProviderKind { Qwen, QwenChina, DeepSeek, Kimi, OpenAI, Gemini, Claude, Custom }
public enum ProviderProtocol { ChatCompletions, AnthropicMessages }
public enum JsonResponseMode { Automatic, Schema, Object, Prompt }
public enum TokenParameter { Automatic, MaxTokens, MaxCompletionTokens }
public enum RegisterPreference { Both, FriendsCasual, PoliteCasual }
public enum SlangLevel { Off, Light, Trendy }
public enum Register { Casual, Polite }
public enum NoSelectionScope { WholeField, CurrentLine }

public sealed record Suggestion(string Text, Register Register);

public static class Providers
{
    public static string Title(ProviderKind kind) => kind switch
    {
        ProviderKind.Qwen => "Qwen / 百炼（国际站）",
        ProviderKind.QwenChina => "Qwen / 百炼（中国站）",
        ProviderKind.DeepSeek => "DeepSeek",
        ProviderKind.Kimi => "Kimi",
        ProviderKind.OpenAI => "OpenAI",
        ProviderKind.Gemini => "Gemini",
        ProviderKind.Claude => "Claude",
        _ => "自定义",
    };

    public static ProviderConfig Default(ProviderKind kind) => new()
    {
        BaseUrl = kind switch
        {
            ProviderKind.Qwen => "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
            ProviderKind.QwenChina => "https://dashscope.aliyuncs.com/compatible-mode/v1",
            ProviderKind.DeepSeek => "https://api.deepseek.com/v1",
            ProviderKind.Kimi => "https://api.moonshot.ai/v1",
            ProviderKind.OpenAI => "https://api.openai.com/v1",
            ProviderKind.Gemini => "https://generativelanguage.googleapis.com/v1beta/openai",
            ProviderKind.Claude => "https://api.anthropic.com/v1",
            _ => "",
        },
        Protocol = kind == ProviderKind.Claude ? ProviderProtocol.AnthropicMessages : ProviderProtocol.ChatCompletions,
        DisableThinking = kind is ProviderKind.Qwen or ProviderKind.QwenChina,
    };

    public static bool IsQwen(ProviderKind kind) => kind is ProviderKind.Qwen or ProviderKind.QwenChina;
}

public sealed class ProviderConfig
{
    public string BaseUrl { get; set; } = "";
    public string Model { get; set; } = "";
    public ProviderProtocol Protocol { get; set; } = ProviderProtocol.ChatCompletions;
    public JsonResponseMode ResponseMode { get; set; } = JsonResponseMode.Automatic;
    public TokenParameter TokenParameter { get; set; } = TokenParameter.Automatic;
    public bool DisableThinking { get; set; }

    public ProviderConfig Clone() => (ProviderConfig)MemberwiseClone();

    /// Mirrors ProviderConfiguration.endpoint in NaturalSuggestCore.
    public Uri Endpoint(string path)
    {
        var raw = BaseUrl.Trim();
        while (raw.EndsWith('/')) raw = raw[..^1];
        if (raw.Contains('{') || !Uri.TryCreate(raw, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps
            || string.IsNullOrEmpty(uri.Host) || !string.IsNullOrEmpty(uri.UserInfo) || !string.IsNullOrEmpty(uri.Query)
            || !string.IsNullOrEmpty(uri.Fragment))
            throw new SuggestionException(Diagnostic.Configuration);
        var absolutePath = uri.AbsolutePath.TrimEnd('/');
        if (absolutePath.EndsWith("/" + path)) return uri;
        if (absolutePath.EndsWith("/responses") || absolutePath.EndsWith("/messages") || absolutePath.EndsWith("/chat/completions"))
            throw new SuggestionException(Diagnostic.Configuration);
        return new Uri(raw + "/" + path);
    }
}

public sealed class AppSettings
{
    public bool Consent { get; set; }
    public SuggestionLanguage Language { get; set; } = SuggestionLanguage.Japanese;
    public ProviderKind Provider { get; set; } = ProviderKind.Qwen;
    public Dictionary<ProviderKind, ProviderConfig> ProviderConfigs { get; set; } = new();
    public RegisterPreference RegisterPreference { get; set; } = RegisterPreference.Both;
    public SlangLevel SlangLevel { get; set; } = SlangLevel.Light;
    public int MaximumSuggestions { get; set; } = 5;
    public int DailyCap { get; set; } = 200;
    public string Hotkey { get; set; } = HotkeyPreset.Default;
    /// What the hotkey checks when nothing is selected.
    public NoSelectionScope NoSelection { get; set; } = NoSelectionScope.WholeField;
    /// Experimental: suggest automatically after a typing pause (UI Automation; not every app exposes its text).
    public bool AutoMode { get; set; }
    public int AutoPauseMilliseconds { get; set; } = 800;
    public int MinimumLength { get; set; } = 4;
    public bool HighlightChanges { get; set; } = true;
    public string BudgetDay { get; set; } = "";
    public int BudgetUsed { get; set; }

    [JsonIgnore] public int SuggestionLimit => Math.Clamp(MaximumSuggestions, 1, 10);

    public ProviderConfig Config(ProviderKind kind) =>
        ProviderConfigs.TryGetValue(kind, out var config) ? config : Providers.Default(kind);

    static readonly string Folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "NaturalKana");
    static readonly string FilePath = Path.Combine(Folder, "settings.json");
    static readonly JsonSerializerOptions Options = new() { WriteIndented = true, Converters = { new JsonStringEnumConverter() } };

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath), Options) ?? new AppSettings();
        }
        catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException) { }
        return new AppSettings();
    }

    public void Save()
    {
        Directory.CreateDirectory(Folder);
        var temp = FilePath + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(this, Options));
        File.Move(temp, FilePath, overwrite: true);
    }

    /// Counts every HTTP request against the local daily cap (0 = unlimited).
    public bool ReserveRequest()
    {
        var today = DateTime.Now.ToString("yyyy-MM-dd");
        if (BudgetDay != today) { BudgetDay = today; BudgetUsed = 0; }
        if (DailyCap > 0 && BudgetUsed + 1 > DailyCap) return false;
        BudgetUsed++;
        try { Save(); } catch (IOException) { }
        return true;
    }
}

public static class HotkeyPreset
{
    public const string Default = "Ctrl+Alt+J";
}
