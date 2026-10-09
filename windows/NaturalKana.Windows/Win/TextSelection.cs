using NaturalKana.Windows.Core;

namespace NaturalKana.Windows.Win;

internal sealed record CapturedText(string Text, bool AutoSelected, bool WholeField);

internal interface ITextSelection
{
    bool IsTargetActive { get; }
    Task<string?> CopyAsync();
    Task SelectAllAsync();
    Task SelectLineAsync();
    Task<bool> PasteAsync(string text);
}

internal static class TextSelection
{
    public static async Task<CapturedText?> CaptureAsync(ITextSelection input, NoSelectionScope scope, bool selectAll)
    {
        if (!input.IsTargetActive) return null;
        string? text = null;
        var hadSelection = false;
        var wholeField = false;
        if (!selectAll)
        {
            text = await input.CopyAsync();
            hadSelection = !string.IsNullOrWhiteSpace(text);
        }
        if (!input.IsTargetActive) return null;
        if (selectAll || !hadSelection && scope == NoSelectionScope.WholeField)
        {
            await input.SelectAllAsync();
            if (!input.IsTargetActive) return null;
            text = await input.CopyAsync();
            wholeField = !string.IsNullOrWhiteSpace(text);
        }
        // An explicit whole-field check must not silently fall back to a different range.
        if (!selectAll && string.IsNullOrWhiteSpace(text))
        {
            if (!input.IsTargetActive) return null;
            await input.SelectLineAsync();
            if (!input.IsTargetActive) return null;
            text = await input.CopyAsync();
        }
        return !input.IsTargetActive || string.IsNullOrWhiteSpace(text)
            ? null : new CapturedText(text, !hadSelection, wholeField);
    }

    public static async Task<bool> ReplaceAsync(ITextSelection input, CapturedText capture, string replacement)
    {
        if (!input.IsTargetActive) return false;
        if (capture.WholeField)
        {
            await input.SelectAllAsync();
            if (!input.IsTargetActive) return false;
        }
        var selected = await input.CopyAsync();
        if (!input.IsTargetActive || !string.Equals(selected, capture.Text, StringComparison.Ordinal)) return false;
        return await input.PasteAsync(replacement);
    }
}
