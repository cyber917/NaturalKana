namespace NaturalKana.Windows.Core;

public sealed record SuggestionSpan(string Text, bool Changed);

/// Port of SuggestionDiff: local grapheme LCS, no extra model request.
public static class SuggestionDiff
{
    public static List<SuggestionSpan> Spans(string original, string candidate)
    {
        if (original == candidate) return [new(candidate, false)];
        var old = JapaneseText.Graphemes(JapaneseText.Nfkc(original));
        var @new = JapaneseText.Graphemes(candidate);
        if (old.Length == 0 || old.Length > 200 || @new.Length > 600) return [new(candidate, false)];

        var width = @new.Length + 1;
        var lengths = new int[(old.Length + 1) * width];
        for (var i = old.Length - 1; i >= 0; i--)
            for (var j = @new.Length - 1; j >= 0; j--)
                lengths[i * width + j] = old[i] == @new[j]
                    ? 1 + lengths[(i + 1) * width + j + 1]
                    : Math.Max(lengths[(i + 1) * width + j], lengths[i * width + j + 1]);

        var changed = Enumerable.Repeat(true, @new.Length).ToArray();
        int a = 0, b = 0;
        while (a < old.Length && b < @new.Length)
        {
            if (old[a] == @new[b]) { changed[b] = false; a++; b++; }
            else if (lengths[(a + 1) * width + b] >= lengths[a * width + b + 1]) a++;
            else b++;
        }
        // A deletion has no inserted text to color; mark its surviving boundary.
        if (!changed.Contains(true) && @new.Length > 0 && !old.SequenceEqual(@new))
        {
            var first = Enumerable.Range(0, Math.Min(old.Length, @new.Length)).FirstOrDefault(k => old[k] != @new[k], @new.Length - 1);
            changed[Math.Min(first, @new.Length - 1)] = true;
        }

        var result = new List<SuggestionSpan>();
        for (var k = 0; k < @new.Length; k++)
        {
            if (result.Count > 0 && result[^1].Changed == changed[k])
                result[^1] = result[^1] with { Text = result[^1].Text + @new[k] };
            else
                result.Add(new(@new[k], changed[k]));
        }
        return result;
    }
}
