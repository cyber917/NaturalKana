using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace NaturalKana.Windows.Core;

/// A suggestion language, identified by its language pack folder (Resources/Languages/<Id>), as in NaturalSuggestCore.
[JsonConverter(typeof(SuggestionLanguageConverter))]
public readonly record struct SuggestionLanguage(string Id)
{
    public static readonly SuggestionLanguage Japanese = new("japanese");
    public static readonly SuggestionLanguage English = new("english");
    public static readonly SuggestionLanguage Chinese = new("chinese");
    public LanguagePack Pack => Id is not null && LanguagePack.ById.TryGetValue(Id, out var pack) ? pack : LanguagePack.ById["japanese"];
    public override string ToString() => Id;
}

/// Earlier builds saved "Japanese"/"English"/"Chinese"; a language without a bundled pack falls back to Japanese.
sealed class SuggestionLanguageConverter : JsonConverter<SuggestionLanguage>
{
    public override SuggestionLanguage Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options)
    {
        var id = reader.TokenType == JsonTokenType.String ? reader.GetString()?.ToLowerInvariant() : null;
        return id is not null && LanguagePack.ById.ContainsKey(id) ? new(id) : SuggestionLanguage.Japanese;
    }
    public override void Write(Utf8JsonWriter writer, SuggestionLanguage value, JsonSerializerOptions options) => writer.WriteStringValue(value.Id);
}

/// Per-language behaviour, read from the language packs shared with iPhone/Mac.
public static class Languages
{
    public static IReadOnlyList<SuggestionLanguage> All => LanguagePack.All.Select(p => new SuggestionLanguage(p.Id)).ToList();
    public static string Title(SuggestionLanguage language) => UIText.T(language.Pack.Title);
    public static string PromptName(SuggestionLanguage language) => language.Pack.PromptName;
    public static string Key(SuggestionLanguage language) => language.Pack.Id;
    public static string TestDraft(SuggestionLanguage language) => language.Pack.TestDraft;

    /// Group titles are in the suggestion language itself, as on iPhone/Mac.
    public static string RegisterTitle(SuggestionLanguage language, Register register) => register == Register.Kansai
        ? "関西弁"
        : language.Pack.RegisterTitles.GetValueOrDefault(register.ToString().ToLowerInvariant(), register.ToString());

    public static string NotThisLanguage(SuggestionLanguage language) =>
        UIText.T("这看起来不是%@句子，没有发送。（设置里可以切换建议语言）", $"{Title(language)}");

    /// Mirrors SuggestionLanguage.detect: a language's signal (hiragana, common Chinese function words…) decides;
    /// otherwise the primary language wins. Kanji-only text is not guessed as Chinese for a Japanese-primary user.
    public static SuggestionLanguage? Detect(string text, SuggestionLanguage primary)
    {
        var accepted = All.Where(l => AcceptsDraft(l, text)).ToList();
        if (accepted.Count == 0) return null;
        var normalized = JapaneseText.Nfkc(text);
        var signaled = accepted.Where(l => l.Pack.Detect.Signal is { } signal && Regex.IsMatch(normalized, signal))
            .OrderBy(l => l.Pack.Detect.Priority ?? int.MaxValue).ToList();
        if (signaled.Count > 0) return signaled[0];
        if (accepted.Contains(primary)) return primary;
        foreach (var language in accepted)
            if (!(language.Pack.Detect.AmbiguousWith ?? []).Contains(primary.Id)) return language;
        return null;
    }

    public static bool AcceptsDraft(SuggestionLanguage language, string text) => language.Pack.Rules switch
    {
        "japanese" => JapaneseText.IsJapaneseDraft(text),
        "chinese" => ChineseText.IsChineseDraft(text),
        "english" => EnglishText.IsEnglishDraft(text),
        _ => GenericText.IsDraft(language.Pack.Generic, text),
    };

    public static bool AcceptsCandidate(SuggestionLanguage language, string text, string original) => language.Pack.Rules switch
    {
        "japanese" => JapaneseText.AcceptsCandidate(text, original),
        "chinese" => ChineseText.AcceptsCandidate(text, original),
        "english" => EnglishText.IsEnglish(text),
        _ => GenericText.AcceptsCandidate(language.Pack.Generic, text, original),
    };
}

/// Port of EnglishDraftProfile / EnglishProfile. Without the OS language recognizer,
/// a sentence must contain a common English word to count as English (fails closed).
public static partial class EnglishText
{
    static readonly HashSet<string> Anchors =
    [
        "i", "i'm", "i've", "i'll", "i'd", "you", "you're", "your", "we", "we're", "they", "he", "she", "it", "it's", "the", "a", "an",
        "is", "are", "was", "were", "to", "my", "me", "can", "could", "please", "have", "has", "don't", "doesn't", "not", "this", "that",
        "thanks", "thank", "hello", "hi", "hey", "sorry", "yes", "no", "okay", "ok", "and", "but", "so", "if", "of", "in", "on", "at",
        "for", "with", "be", "do", "does", "did", "will", "would", "should", "what", "how", "why", "when", "where", "who", "us", "our",
    ];
    static readonly string[] Denied = ["ignore previous instructions", "ignore all instructions", "ignore instructions", "system prompt", "developer message", "翻译", "翻訳", "指示を無視"];

    [GeneratedRegex(@"^\s*(please\s+)?(translate|rewrite in|respond in)\b")] private static partial Regex RequestRegex();
    [GeneratedRegex(@"[\p{L}']+")] private static partial Regex WordRegex();

    static bool IsLatin(Rune r) => Rune.IsLetter(r) && (r.Value is >= 65 and <= 122 or >= 0xC0 and <= 0x24F);

    static List<string> Words(string text) =>
        WordRegex().Matches(text.ToLowerInvariant().Replace('’', '\'')).Select(m => m.Value).ToList();

    static bool IsUsable(string text)
    {
        if (text.Any(char.IsControl) || text.Distinct().Count() <= 1) return false;
        var lower = text.ToLowerInvariant();
        return !Denied.Any(lower.Contains) && !RequestRegex().IsMatch(lower);
    }

    /// Learner English, possibly with a few foreign words as placeholders.
    public static bool IsEnglishDraft(string text)
    {
        var normalized = JapaneseText.Nfkc(text);
        if (!IsUsable(normalized)) return false;
        var letters = normalized.EnumerateRunes().Where(Rune.IsLetter).ToList();
        var latin = letters.Count(IsLatin);
        var foreignRuns = Regex.Split(normalized, @"[^\p{L}]+").Count(run => run.EnumerateRunes().Any(r => !IsLatin(r)));
        if (latin < 2 || foreignRuns > 3 || (double)latin / Math.Max(1, letters.Count) < 0.5) return false;
        var words = Words(normalized);
        // Single-word drafts like "Thanks!" pass via the anchor list.
        return words.Count > 0 && words.Any(Anchors.Contains);
    }

    /// Candidates must be English only.
    public static bool IsEnglish(string text)
    {
        var normalized = JapaneseText.Nfkc(text);
        return IsUsable(normalized) && normalized.EnumerateRunes().Where(Rune.IsLetter).All(IsLatin) && IsEnglishDraft(normalized);
    }
}
