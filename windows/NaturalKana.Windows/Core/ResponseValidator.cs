using System.Text;
using System.Text.Json;

namespace NaturalKana.Windows.Core;

public enum Assessment { Natural, Rewrite, Unsupported }

public sealed record ValidationReport(IReadOnlyList<Suggestion> Suggestions, int ReceivedCount, Assessment? Assessment)
{
    public string? EmptyMessage =>
        Suggestions.Count > 0 ? null
        : ReceivedCount > 0 ? $"模型返回了 {ReceivedCount} 条候选，但都没通过格式或语言检查"
        : Assessment == Core.Assessment.Natural ? "这句话已经很自然了"
        : Assessment == Core.Assessment.Unsupported ? "模型认为这句不是可以修改的草稿，没有给出建议"
        : "模型返回了空候选；这不代表原句一定自然";
}

/// Port of ResponseValidator: strict JSON shape, register filter, language and duplicate checks.
public static class ResponseValidator
{
    public static ValidationReport Inspect(string json, string draft, AppSettings settings)
    {
        if (Encoding.UTF8.GetByteCount(json) > 32_768) throw new SuggestionException(Diagnostic.InvalidResponse);
        JsonDocument doc;
        try { doc = JsonDocument.Parse(json); }
        catch (JsonException) { throw new SuggestionException(Diagnostic.InvalidResponse); }
        using (doc)
        {
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object
                || root.EnumerateObject().Any(p => p.Name is not ("suggestions" or "assessment"))
                || !root.TryGetProperty("suggestions", out var rows) || rows.ValueKind != JsonValueKind.Array
                || rows.GetArrayLength() > 10)
                throw new SuggestionException(Diagnostic.InvalidResponse);

            Assessment? assessment = null;
            if (root.TryGetProperty("assessment", out var value))
            {
                if (value.ValueKind != JsonValueKind.String || !Enum.TryParse<Assessment>(value.GetString(), true, out var known)
                    || (known == Assessment.Rewrite ? rows.GetArrayLength() == 0 : rows.GetArrayLength() != 0))
                    throw new SuggestionException(Diagnostic.InvalidResponse);
                assessment = known;
            }

            var original = JapaneseText.Nfkc(draft);
            var originalLength = JapaneseText.Length(original);
            var seen = new HashSet<string>();
            var accepted = new List<Suggestion>();
            foreach (var row in rows.EnumerateArray())
            {
                if (row.ValueKind != JsonValueKind.Object) continue;
                var names = row.EnumerateObject().Select(p => p.Name).ToHashSet();
                if (!names.SetEquals(["text", "register"])) continue;
                if (row.GetProperty("text").ValueKind != JsonValueKind.String || row.GetProperty("register").ValueKind != JsonValueKind.String) continue;
                if (!Enum.TryParse<Register>(row.GetProperty("register").GetString(), true, out var register)) continue;
                var text = JapaneseText.Nfkc(row.GetProperty("text").GetString()!).Trim();
                if (text.Length == 0 || text.Any(c => c is '\n' or '\r' || char.IsControl(c)) || text == original
                    || JapaneseText.Length(text) > 3 * originalLength
                    || !Languages.AcceptsCandidate(settings.Language, text, original))
                    continue;
                // Dialect rows are their own group: only the selected dialect, never filtered by casual/polite preference.
                if (Dialects.IsDialect(register)
                        ? register != Dialects.RegisterOf(settings.ActiveDialect)
                        : (settings.RegisterPreference == RegisterPreference.FriendsCasual && register != Register.Casual)
                          || (settings.RegisterPreference == RegisterPreference.PoliteCasual && register != Register.Polite))
                    continue;
                // Reject newly introduced emoji/symbols.
                if (text.EnumerateRunes().Where(IsEmoji).Any(r => !original.EnumerateRunes().Contains(r))) continue;
                if (!seen.Add(text)) continue;
                accepted.Add(new Suggestion(text, register));
                if (accepted.Count >= settings.SuggestionLimit) break;
            }
            // Keep model ranking within each register; casual, polite, then dialect. Same order for display and acceptance.
            var grouped = Enum.GetValues<Register>().SelectMany(r => accepted.Where(s => s.Register == r)).ToList();
            return new ValidationReport(grouped, rows.GetArrayLength(), assessment);
        }
    }

    static bool IsEmoji(Rune r) => r.Value is 0xFE0F or >= 0x1F000 and <= 0x1FAFF or >= 0x2600 and <= 0x27BF;
}
