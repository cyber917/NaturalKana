using System.Globalization;
using System.IO;
using System.Text.Json;

namespace NaturalKana.Windows.Core;

/// Language of NaturalKana's own interface. Mirrors InterfaceLanguage in NaturalSuggestCore.
public enum InterfaceLanguage { System, Chinese, English, Japanese }

/// Interface strings keyed by their Simplified Chinese source text. Translations come from the
/// ui_strings.json shared with iPhone/Mac; a missing entry shows the Chinese. Placeholders are %@, filled in order.
public static class UIText
{
    public static InterfaceLanguage Language { get; set; } = InterfaceLanguage.System;

    static readonly Lazy<Dictionary<string, Dictionary<string, string>>> Table = new(() =>
    {
        try
        {
            using var stream = typeof(UIText).Assembly.GetManifestResourceStream("ui_strings.json");
            if (stream is null) return [];
            return JsonSerializer.Deserialize<Dictionary<string, Dictionary<string, string>>>(stream) ?? [];
        }
        catch (Exception ex) when (ex is JsonException or IOException) { return []; }
    });
    internal static IReadOnlyDictionary<string, Dictionary<string, string>> Entries => Table.Value;

    /// Each language names itself, so a user who cannot read the current interface can still find theirs.
    public static string Title(InterfaceLanguage language) => language switch
    {
        InterfaceLanguage.Chinese => "中文",
        InterfaceLanguage.English => "English",
        InterfaceLanguage.Japanese => "日本語",
        _ => T("跟随系统"),
    };

    public static InterfaceLanguage Resolve(InterfaceLanguage language, CultureInfo? culture = null)
    {
        if (language != InterfaceLanguage.System) return language;
        var name = (culture ?? CultureInfo.CurrentUICulture).Name.ToLowerInvariant();
        return name.StartsWith("zh") ? InterfaceLanguage.Chinese : name.StartsWith("ja") ? InterfaceLanguage.Japanese : InterfaceLanguage.English;
    }

    public static string T(string chinese, params string[] args) => Translate(chinese, Resolve(Language), args);

    public static string Translate(string chinese, InterfaceLanguage language, params string[] args)
    {
        var code = language switch { InterfaceLanguage.English => "en", InterfaceLanguage.Japanese => "ja", _ => null };
        var template = code is not null && Table.Value.TryGetValue(chinese, out var entry) && entry.TryGetValue(code, out var text) ? text : chinese;
        // Fill left to right; an argument that itself contains %@ is not substituted again.
        var result = new System.Text.StringBuilder();
        var rest = template;
        foreach (var arg in args)
        {
            var at = rest.IndexOf("%@", StringComparison.Ordinal);
            if (at < 0) break;
            result.Append(rest, 0, at).Append(arg);
            rest = rest[(at + 2)..];
        }
        return result.Append(rest).ToString();
    }
}
