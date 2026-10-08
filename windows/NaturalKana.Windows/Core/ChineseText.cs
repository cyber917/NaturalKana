using System.Text;

namespace NaturalKana.Windows.Core;

/// Port of ChineseDraftProfile / ChineseProfile from NaturalSuggestCore. Both sides use plain
/// script counts (no OS language recognizer), so the rules match exactly.
public static class ChineseText
{
    internal static readonly HashSet<string> LatinAllowlist = ["OK", "AI", "App", "app", "APP", "PDF", "URL", "ID", "Wi", "Fi", "KTV", "emo", "yyds", "vlog"];
    /// Common Traditional or Japanese-only forms whose Simplified form is different.
    const string NotSimplified = "們這說請謝飯嗎麼讓給還過聽歡話幫樣見來時國會學對個為與東車門開問間關長頭電體氣気動點認讀語書買賣覺親視駅図歩様済広辺発楽実経続紙網絡隣働売円応変戦検験録";
    /// Characters that are frequent in Chinese but rare in kanji-only Japanese.
    internal const string Markers = "的了吗呢吧们这那你我他她很没说么啊呀给让还过请谢";
    static readonly string[] Denied = ["翻译", "翻譯", "翻訳", "译成", "翻成", "忽略指令", "忽略之前", "系统提示", "提示词", "ignore instructions", "system prompt"];

    static bool IsHiragana(int v) => v is >= 0x3041 and <= 0x3096;
    static List<int> Scalars(string text) => text.EnumerateRunes().Where(r => !Rune.IsWhiteSpace(r)).Select(r => r.Value).ToList();
    static bool IsLetter(int v) => Rune.IsLetter(new Rune(v));

    /// Han share of the letters; each foreign word counts as at most two slots.
    static double HanRatio(string text)
    {
        var letters = Scalars(text).Where(IsLetter).ToList();
        var han = letters.Count(JapaneseText.IsHan);
        var latin = letters.Count(v => v < 128);
        var weighted = letters.Count - latin + JapaneseText.LatinWords(text).Sum(w => Math.Min(2, w.Length));
        return (double)han / Math.Max(1, weighted);
    }

    /// Hiragana carries Japanese grammar; a Chinese draft may only borrow a short word.
    static bool LooksJapanese(string text)
    {
        var all = Scalars(text);
        var hiragana = all.Count(IsHiragana);
        return hiragana > 2 && hiragana * 3 > all.Count(JapaneseText.IsHan);
    }

    static bool HasDenied(string normalized) => Denied.Any(normalized.ToLowerInvariant().Contains);

    /// Learner Chinese, possibly with Japanese or English placeholder words.
    public static bool IsChineseDraft(string text)
    {
        var normalized = JapaneseText.Nfkc(text);
        if (HasDenied(normalized) || normalized.Any(char.IsControl) || JapaneseText.Graphemes(normalized).Distinct().Count() <= 1) return false;
        if (Scalars(normalized).Count(JapaneseText.IsHan) < 2 || LooksJapanese(normalized)) return false;
        return HanRatio(normalized) >= 0.5;
    }

    /// Candidates must be Simplified Chinese: no kana, no Traditional/Japanese-only forms, and Latin words
    /// only from the allowlist or as proper nouns (containing an uppercase letter) already in the draft.
    public static bool AcceptsCandidate(string text, string original)
    {
        var normalized = JapaneseText.Nfkc(text);
        if (HasDenied(normalized) || normalized.Any(char.IsControl) || JapaneseText.Graphemes(normalized).Distinct().Count() <= 1) return false;
        var scalars = Scalars(normalized);
        if (scalars.Any(JapaneseText.IsKana) || normalized.Any(c => NotSimplified.Contains(c)) || !scalars.Any(JapaneseText.IsHan)) return false;
        var properNouns = JapaneseText.LatinWords(JapaneseText.Nfkc(original)).Where(w => w.Any(char.IsUpper)).ToHashSet();
        if (!JapaneseText.LatinWords(normalized).All(w => LatinAllowlist.Contains(w) || properNouns.Contains(w))) return false;
        return HanRatio(normalized) >= 0.6;
    }
}
