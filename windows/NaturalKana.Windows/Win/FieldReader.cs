using System.Windows.Automation;
using System.Windows.Automation.Text;

namespace NaturalKana.Windows.Win;

/// The paragraph the caret is in, read through UI Automation (the same interface screen readers use).
public sealed record FieldSnapshot(string ElementId, IntPtr Window, string Before, string After, Native.POINT Anchor, bool ValueOnly)
{
    /// The whole paragraph; auto mode only triggers when the caret is at its end.
    public string Text => Before + After;
}

/// Reads and edits the focused text field of another app. All calls are blocking COM calls:
/// run them off the UI thread. Any app that does not expose its text simply returns null.
public static class FieldReader
{
    const int MaxLength = 400;

    public static FieldSnapshot? Read()
    {
        try
        {
            var element = AutomationElement.FocusedElement;
            if (element is null) return null;
            var current = element.Current;
            if (current.ProcessId == Environment.ProcessId || current.IsPassword || !current.IsEnabled) return null;
            // Any control exposing a text model counts; plain values only for edit boxes.
            var editable = current.ControlType == ControlType.Edit || current.ControlType == ControlType.Document;
            var id = string.Join(".", element.GetRuntimeId());
            var window = Native.GetForegroundWindow();

            if (element.TryGetCurrentPattern(TextPattern.Pattern, out var patternObject))
            {
                var pattern = (TextPattern)patternObject;
                var selection = pattern.GetSelection();
                if (selection.Length != 1) return null;
                var caret = selection[0];
                if (caret.GetText(1).Length > 0) return null; // the user has a selection; leave it to the hotkey
                var paragraph = caret.Clone();
                paragraph.ExpandToEnclosingUnit(TextUnit.Paragraph);
                var before = paragraph.Clone();
                before.MoveEndpointByRange(TextPatternRangeEndpoint.End, caret, TextPatternRangeEndpoint.Start);
                var after = paragraph.Clone();
                after.MoveEndpointByRange(TextPatternRangeEndpoint.Start, caret, TextPatternRangeEndpoint.End);
                var beforeText = before.GetText(MaxLength).TrimEnd('\r', '\n');
                var afterText = after.GetText(MaxLength).TrimEnd('\r', '\n');
                return new FieldSnapshot(id, window, beforeText, afterText, Anchor(before, current), false);
            }
            if (editable && element.TryGetCurrentPattern(ValuePattern.Pattern, out var valueObject))
            {
                var value = ((ValuePattern)valueObject).Current.Value ?? "";
                if (value.Length > MaxLength || value.Contains('\n')) return null;
                // No caret information: assume it is at the end of a single-line box.
                return new FieldSnapshot(id, window, value, "", Anchor(null, current), true);
            }
        }
        catch (Exception ex) when (ex is ElementNotAvailableException or InvalidOperationException
                                       or System.Runtime.InteropServices.COMException or ArgumentException) { }
        return null;
    }

    static Native.POINT Anchor(TextPatternRange? before, AutomationElement.AutomationElementInformation current)
    {
        try
        {
            var rects = before?.GetBoundingRectangles();
            if (rects is { Length: > 0 })
            {
                var last = rects[^1];
                return new Native.POINT { X = (int)last.Right, Y = (int)last.Bottom };
            }
        }
        catch (Exception ex) when (ex is ElementNotAvailableException or InvalidOperationException or System.Runtime.InteropServices.COMException) { }
        var box = current.BoundingRectangle;
        if (!box.IsEmpty && box.Width > 0) return new Native.POINT { X = (int)box.Left + 8, Y = (int)box.Bottom };
        Native.GetCursorPos(out var cursor);
        return cursor;
    }

    /// Selects the text that will be replaced, after checking the field still holds the same draft.
    /// Returns false when the field changed or cannot be selected; the caller then copies instead.
    public static bool SelectForReplace(FieldSnapshot expected)
    {
        try
        {
            var element = AutomationElement.FocusedElement;
            if (element is null || string.Join(".", element.GetRuntimeId()) != expected.ElementId) return false;
            if (expected.ValueOnly)
            {
                var value = ((ValuePattern)element.GetCurrentPattern(ValuePattern.Pattern)).Current.Value;
                if (value != expected.Before) return false;
                Native.Chord(Native.VK_CONTROL, Native.VK_A);
                return true;
            }
            var pattern = (TextPattern)element.GetCurrentPattern(TextPattern.Pattern);
            var caret = pattern.GetSelection().Single();
            var paragraph = caret.Clone();
            paragraph.ExpandToEnclosingUnit(TextUnit.Paragraph);
            var before = paragraph.Clone();
            before.MoveEndpointByRange(TextPatternRangeEndpoint.End, caret, TextPatternRangeEndpoint.Start);
            var after = paragraph.Clone();
            after.MoveEndpointByRange(TextPatternRangeEndpoint.Start, caret, TextPatternRangeEndpoint.End);
            if (before.GetText(MaxLength).TrimEnd('\r', '\n') != expected.Before || after.GetText(MaxLength).TrimEnd('\r', '\n').Length > 0) return false;
            before.Select();
            return true;
        }
        catch (Exception ex) when (ex is ElementNotAvailableException or InvalidOperationException
                                       or System.Runtime.InteropServices.COMException or ArgumentException) { return false; }
    }
}
