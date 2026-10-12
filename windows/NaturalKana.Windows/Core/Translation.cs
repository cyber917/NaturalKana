using System.Text;
using System.Text.RegularExpressions;

namespace NaturalKana.Windows.Core;

public sealed record TranslationRequest(string Draft, SuggestionLanguage Target);

/// Text-only Qwen-MT uses a single user message and returns plain text, without a register.
public static class Translation
{
    public static bool IsModel(string model) => new[] { "qwen-mt-flash", "qwen-mt-plus", "qwen-mt-lite", "qwen-mt-turbo" }
        .Any(name => model.Trim().Equals(name, StringComparison.OrdinalIgnoreCase)
            || model.Trim().StartsWith(name + "-", StringComparison.OrdinalIgnoreCase));

    public static string TargetName(SuggestionLanguage language) => language.Id switch
    {
        "japanese" => "Japanese",
        "english" => "English",
        "chinese" => "Chinese",
        "korean" => "Korean",
        "french" => "French",
        "russian" => "Russian",
        _ => throw new SuggestionException(Diagnostic.Configuration),
    };

    public static bool IsDraft(string text) => JapaneseText.Length(text.Trim()) is >= 2 and <= 200
        && !text.Any(char.IsControl) && text.EnumerateRunes().Any(Rune.IsLetter);

    // Translation may legitimately contain words such as "translate" or "instructions".
    // Check the output script without applying the rewrite mode's command-word denylist.
    public static bool AcceptsCandidate(SuggestionLanguage language, string text)
    {
        var letters = text.EnumerateRunes().Where(Rune.IsLetter).ToList();
        if (letters.Count == 0) return false;
        bool Own(Rune r) => language.Id switch
        {
            "japanese" => JapaneseText.IsKana(r.Value) || JapaneseText.IsHan(r.Value),
            "chinese" => JapaneseText.IsHan(r.Value),
            "english" => r.Value is >= 65 and <= 122 or >= 0xC0 and <= 0x24F,
            _ => language.Pack.Generic is { } rules && Regex.IsMatch(r.ToString(), rules.Letters),
        };
        return letters.Count(Own) >= letters.Count * 0.6
            && (language.Id != "japanese" || letters.Any(r => JapaneseText.IsKana(r.Value)))
            && (language.Id != "chinese" || !letters.Any(r => JapaneseText.IsKana(r.Value)));
    }
}
