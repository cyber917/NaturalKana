using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace NaturalKana.Windows.Core;

/// Port of JapaneseProfile / JapaneseDraftProfile from NaturalSuggestCore.
/// Windows has no NLLanguageRecognizer, so the final OS language check is omitted;
/// the system prompt still returns "unsupported" for non-Japanese drafts.
public static partial class JapaneseText
{
    public static string Nfkc(string text) => text.Normalize(NormalizationForm.FormKC);

    /// Grapheme count, matching Swift's String.count.
    public static int Length(string text) => new StringInfo(text).LengthInTextElements;

    public static string[] Graphemes(string text)
    {
        var result = new List<string>();
        var e = StringInfo.GetTextElementEnumerator(text);
        while (e.MoveNext()) result.Add(e.GetTextElement());
        return [.. result];
    }

    static IEnumerable<int> Scalars(string text)
    {
        foreach (var rune in text.EnumerateRunes()) yield return rune.Value;
    }

    public static bool IsKana(int v) => v is >= 0x3041 and <= 0x3096 or >= 0x30A1 and <= 0x30FA or 0x30FC;
    public static bool IsHan(int v) => v is >= 0x3400 and <= 0x9FFF or >= 0x20000 and <= 0x3134F;
    const string Punctuation = "。、！？!?「」『』（）()・ー〜～….,:：;；【】0123456789";
    static bool IsPunctuation(int v) => v <= 0xFFFF && Punctuation.Contains((char)v);
    static bool IsWhitespace(int v) => Rune.IsWhiteSpace(new Rune(v));

    static readonly HashSet<string> LatinAllowlist = ["w", "ww", "www", "LINE", "SNS", "X", "Instagram", "TikTok", "YouTube", "DM", "OK", "NG", "AI", "URL", "PDF"];
    static readonly string[] ChineseMarkers = ["今天", "明天", "昨天", "我们", "你们", "他们", "很累", "很开心", "不知道", "怎么办", "吃饭", "学习日语", "请帮", "我想", "一起去吧", "天气很好"];
    const string UnmistakableSimplified = "这们说请谢饭吗么让给还过听欢话帮样见";
    static readonly string[] Denied = ["翻訳", "翻译", "訳して", "訳せ", "日本語にして", "中国語にして", "英語にして", "指示を無視", "プロンプト", "命令を無視"];

    public static string[] LatinWords(string text) =>
        LatinWordRegex().Matches(text).Select(m => m.Value).ToArray();

    [GeneratedRegex("[A-Za-z]+")] private static partial Regex LatinWordRegex();
    [GeneratedRegex("[一-龯ぁ-ゖァ-ヺー]{2,}(?:[はがをにと]|で(?!す))")] private static partial Regex TopicRegex();

    /// Strict check used for model output.
    public static bool IsJapanese(string text)
    {
        var normalized = Nfkc(text);
        if (ChineseMarkers.Any(normalized.Contains) || normalized.Any(c => UnmistakableSimplified.Contains(c))) return false;
        if (normalized.Distinct().Count() <= 1 && Length(normalized) >= 5) return false;
        var scalars = Scalars(normalized).Where(v => !IsWhitespace(v)).ToList();
        if (scalars.Count == 0 || !scalars.Any(IsKana)) return false;
        if (!LatinWords(normalized).All(LatinAllowlist.Contains)) return false;
        var japanese = scalars.Count(v => IsKana(v) || IsHan(v) || IsPunctuation(v));
        if ((double)japanese / scalars.Count < 0.7) return false;
        return !Denied.Any(normalized.Contains);
    }

    /// Lenient check for drafts: unknown foreign words inside a Japanese sentence are allowed.
    public static bool IsJapaneseDraft(string text)
    {
        if (IsJapanese(text)) return true;
        var normalized = Nfkc(text);
        var lower = normalized.ToLowerInvariant();
        if (Denied.Any(lower.Contains) || lower.Contains("ignore instructions") || lower.Contains("system prompt")) return false;
        if (normalized.Any(char.IsControl)) return false;
        if (Scalars(normalized).Count(IsKana) < 3) return false;
        string[] structure = ["した", "する", "して", "でき", "だから", "けど", "たい", "ない", "だった", "ます", "ました", "ください", "って", "ちゃ", "った", "れる", "られる"];
        var topic = TopicRegex().IsMatch(normalized);
        if (!structure.Any(normalized.Contains) && !(topic && normalized.Contains("です"))) return false;
        var scalars = Scalars(normalized).Where(v => !IsWhitespace(v)).ToList();
        var japanese = scalars.Count(v => IsKana(v) || IsHan(v));
        var latin = scalars.Count(v => v < 128 && char.IsLetter((char)v));
        var weighted = scalars.Count - latin + LatinWords(normalized).Sum(w => Math.Min(2, w.Length));
        return (double)japanese / Math.Max(1, weighted) >= 0.5;
    }

    /// Candidates must be Japanese and must not introduce Latin words absent from the draft.
    public static bool AcceptsCandidate(string text, string original)
    {
        var originalLatin = LatinWords(original).ToHashSet();
        return IsJapanese(text) && LatinWords(text).All(originalLatin.Contains);
    }
}
