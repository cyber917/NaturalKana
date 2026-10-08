using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace NaturalKana.Windows.Core;

/// One suggestion language from NaturalSuggestCore's Resources/Languages/<id>/ (language.json, prompt.txt,
/// optional lexicon.jsonl), embedded as "Languages/<id>/<file>". Mirrors LanguagePack in NaturalSuggestCore.
public sealed class LanguagePack
{
    public sealed class Detection
    {
        public string? Signal { get; init; }
        public int? Priority { get; init; }
        public List<string>? AmbiguousWith { get; init; }
    }
    public sealed class GenericRules
    {
        public string Letters { get; init; } = "[^\\s\\S]";
        public double? DraftShare { get; init; }
        public double? CandidateShare { get; init; }
        public int? MinLetters { get; init; }
        public string? Forbidden { get; init; }
        public List<string>? LatinAllowlist { get; init; }
        public List<string>? Denied { get; init; }
        public string? RequiredPattern { get; init; }
    }

    public string Id { get; private set; } = "";
    public int Order { get; init; }
    public string Title { get; init; } = "";
    public string PromptName { get; init; } = "";
    public string Locale { get; init; } = "";
    public string TestDraft { get; init; } = "";
    public Dictionary<string, string> RegisterTitles { get; init; } = [];
    public string CloseTitle { get; init; } = "";
    public string CopyHint { get; init; } = "";
    public string Rules { get; init; } = "generic";
    public Detection Detect { get; init; } = new();
    public GenericRules? Generic { get; init; }
    public bool? KeepPunctuation { get; init; }
    public bool? RomanizedInput { get; init; }
    public string? WindowsFont { get; init; }
    public string Prompt { get; private set; } = "";
    public List<JsonObject> Lexicon { get; private set; } = [];

    static readonly Lazy<List<LanguagePack>> Loaded = new(Load);
    public static IReadOnlyList<LanguagePack> All => Loaded.Value;
    public static IReadOnlyDictionary<string, LanguagePack> ById => All.ToDictionary(p => p.Id);

    static List<LanguagePack> Load()
    {
        var assembly = typeof(LanguagePack).Assembly;
        // %(RecursiveDir) may produce either slash in the logical name.
        var resources = assembly.GetManifestResourceNames()
            .Select(name => (name, path: name.Replace('\\', '/')))
            .Where(r => r.path.StartsWith("Languages/", StringComparison.Ordinal)).ToList();
        string? Read(string id, string file)
        {
            var match = resources.FirstOrDefault(r => r.path == $"Languages/{id}/{file}");
            if (match.name is null) return null;
            using var stream = assembly.GetManifestResourceStream(match.name)!;
            using var reader = new StreamReader(stream, Encoding.UTF8);
            return reader.ReadToEnd();
        }
        var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        var packs = new List<LanguagePack>();
        foreach (var id in resources.Select(r => r.path.Split('/')).Where(p => p.Length == 3 && p[2] == "language.json").Select(p => p[1]))
        {
            var pack = JsonSerializer.Deserialize<LanguagePack>(Read(id, "language.json")!, options)!;
            pack.Id = id;
            pack.Prompt = Read(id, "prompt.txt") ?? "";
            pack.Lexicon = ParseLexicon(Read(id, "lexicon.jsonl"));
            packs.Add(pack);
        }
        return packs.OrderBy(p => p.Order).ThenBy(p => p.Id, StringComparer.Ordinal).ToList();
    }

    static List<JsonObject> ParseLexicon(string? text)
    {
        if (text is null) return [];
        try { return text.Split('\n', StringSplitOptions.RemoveEmptyEntries).Select(line => JsonNode.Parse(line)!.AsObject()).ToList(); }
        catch (JsonException) { return []; }
    }
}

/// Port of GenericProfile: script checks for languages without hand-tuned rules, driven by language.json.
public static class GenericText
{
    static List<int> Letters(string text) => text.EnumerateRunes().Where(Rune.IsLetter).Select(r => r.Value).ToList();
    static bool IsOwn(LanguagePack.GenericRules rules, int scalar) => Regex.IsMatch(char.ConvertFromUtf32(scalar), rules.Letters);
    static bool Denied(LanguagePack.GenericRules rules, string text) => (rules.Denied ?? []).Any(text.ToLowerInvariant().Contains);
    static bool MatchesLanguage(LanguagePack.GenericRules rules, string text) => rules.RequiredPattern is not { } pattern || Regex.IsMatch(text, pattern);
    static bool Repetitive(string text) => JapaneseText.Graphemes(text).Distinct().Count() <= 1;

    /// Share of own letters; with Latin foreign, each Latin word counts as at most two letters.
    static (int Own, double Share) Share(LanguagePack.GenericRules rules, string text)
    {
        var letters = Letters(text);
        var own = letters.Count(v => IsOwn(rules, v));
        var total = letters.Count;
        if (!IsOwn(rules, 'a'))
        {
            var latin = letters.Count(v => v < 128 && !IsOwn(rules, v));
            total += JapaneseText.LatinWords(text).Sum(w => Math.Min(2, w.Length)) - latin;
        }
        return (own, (double)own / Math.Max(1, total));
    }

    public static bool IsDraft(LanguagePack.GenericRules? rules, string text)
    {
        if (rules is null) return false;
        var normalized = JapaneseText.Nfkc(text);
        if (Denied(rules, normalized) || !MatchesLanguage(rules, normalized) || normalized.Any(char.IsControl) || Repetitive(normalized)) return false;
        var (own, share) = Share(rules, normalized);
        return own >= (rules.MinLetters ?? 2) && share >= (rules.DraftShare ?? 0.5);
    }

    public static bool AcceptsCandidate(LanguagePack.GenericRules? rules, string text, string original)
    {
        if (rules is null) return false;
        var normalized = JapaneseText.Nfkc(text);
        if (Denied(rules, normalized) || !MatchesLanguage(rules, normalized) || normalized.Any(char.IsControl) || Repetitive(normalized)) return false;
        if (rules.Forbidden is { } forbidden && Regex.IsMatch(normalized, forbidden)) return false;
        if (!IsOwn(rules, 'a'))
        {
            // Brand names keep their Latin spelling; lowercase placeholders must be written in the language.
            var properNouns = JapaneseText.LatinWords(JapaneseText.Nfkc(original)).Where(w => w.Any(char.IsUpper)).ToHashSet();
            var allowed = (rules.LatinAllowlist ?? []).ToHashSet();
            if (!JapaneseText.LatinWords(normalized).All(w => allowed.Contains(w) || properNouns.Contains(w))) return false;
        }
        var (own, share) = Share(rules, normalized);
        return own >= 1 && share >= (rules.CandidateShare ?? 0.6);
    }
}
