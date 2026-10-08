using System.Text;
using System.Text.RegularExpressions;

namespace NaturalKana.Windows.Core;

public enum SuggestionLanguage { Japanese, English, Chinese }

/// Per-language behaviour, mirroring SuggestionLanguage in NaturalSuggestCore.
public static class Languages
{
    public static string Title(SuggestionLanguage language) => language switch
    {
        SuggestionLanguage.Japanese => UIText.T("日语"),
        SuggestionLanguage.Chinese => UIText.T("中文"),
        _ => UIText.T("英语"),
    };
    public static string PromptName(SuggestionLanguage language) => language switch
    {
        SuggestionLanguage.Japanese => "Japanese",
        SuggestionLanguage.Chinese => "Simplified Chinese",
        _ => "English",
    };
    public static string Key(SuggestionLanguage language) => language switch
    {
        SuggestionLanguage.Japanese => "japanese",
        SuggestionLanguage.Chinese => "chinese",
        _ => "english",
    };

    public static string TestDraft(SuggestionLanguage language) => language switch
    {
        SuggestionLanguage.Japanese => "今日は仕事があるから、少し待ってください。",
        SuggestionLanguage.Chinese => "我明天有工作，所以请等一点我。",
        _ => "I have work to do, please wait me a moment.",
    };

    public static string RegisterTitle(SuggestionLanguage language, Register register) => (language, register) switch
    {
        (_, Register.Kansai) => "関西弁",
        (SuggestionLanguage.Japanese, Register.Casual) => UIText.T("口语"),
        (SuggestionLanguage.Japanese, _) => UIText.T("敬语"),
        (SuggestionLanguage.Chinese, Register.Casual) => UIText.T("口语"),
        (SuggestionLanguage.Chinese, _) => UIText.T("礼貌"),
        (_, Register.Casual) => "Casual",
        _ => "Polite",
    };

    public static string NotThisLanguage(SuggestionLanguage language) =>
        UIText.T("这看起来不是%@句子，没有发送。（设置里可以切换建议语言）", $"{Title(language)}");

    /// Mirrors SuggestionLanguage.detect: hiragana means Japanese; common Chinese function words mean Chinese;
    /// otherwise the primary language wins. Kanji-only text is not guessed as Chinese for a Japanese-primary user.
    public static SuggestionLanguage? Detect(string text, SuggestionLanguage primary)
    {
        var accepted = Enum.GetValues<SuggestionLanguage>().Where(l => AcceptsDraft(l, text)).ToList();
        if (accepted.Count == 0) return null;
        var normalized = JapaneseText.Nfkc(text);
        var hiragana = normalized.Any(c => c is >= '\u3041' and <= '\u3096');
        var chineseMarked = normalized.Any(c => ChineseText.Markers.Contains(c));
        if (accepted.Contains(SuggestionLanguage.Japanese) && hiragana) return SuggestionLanguage.Japanese;
        if (accepted.Contains(SuggestionLanguage.Chinese) && chineseMarked) return SuggestionLanguage.Chinese;
        if (accepted.Contains(primary)) return primary;
        if (accepted is [SuggestionLanguage.Chinese] && primary == SuggestionLanguage.Japanese) return null;
        return accepted[0];
    }

    public static bool AcceptsDraft(SuggestionLanguage language, string text) => language switch
    {
        SuggestionLanguage.Japanese => JapaneseText.IsJapaneseDraft(text),
        SuggestionLanguage.Chinese => ChineseText.IsChineseDraft(text),
        _ => EnglishText.IsEnglishDraft(text),
    };

    public static bool AcceptsCandidate(SuggestionLanguage language, string text, string original) => language switch
    {
        SuggestionLanguage.Japanese => JapaneseText.AcceptsCandidate(text, original),
        SuggestionLanguage.Chinese => ChineseText.AcceptsCandidate(text, original),
        _ => EnglishText.IsEnglish(text),
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
