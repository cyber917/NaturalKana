using NaturalKana.Windows.Core;
using NaturalKana.Windows.Win;
using Xunit;

namespace NaturalKana.Windows.Tests;

public class TextSelectionTests
{
    sealed class Input(string field, string? selected = null) : ITextSelection
    {
        public string Field = field;
        public string? Selected = selected;
        public bool IsTargetActive { get; set; } = true;
        public bool SupportsSelectAll = true;
        public bool LeaveAfterCopy, LeaveAfterSelect;
        public readonly List<string> Operations = [];
        public Task<string?> CopyAsync()
        {
            Operations.Add("copy");
            if (LeaveAfterCopy) IsTargetActive = false;
            return Task.FromResult(Selected);
        }
        public Task SelectAllAsync()
        {
            Operations.Add("all");
            if (SupportsSelectAll) Selected = Field;
            if (LeaveAfterSelect) IsTargetActive = false;
            return Task.CompletedTask;
        }
        public Task SelectLineAsync()
        {
            Operations.Add("line");
            Selected = Field.Split('\n').Last();
            return Task.CompletedTask;
        }
        public Task<bool> PasteAsync(string text)
        {
            Operations.Add("paste");
            if (!IsTargetActive || Selected is null) return Task.FromResult(false);
            Field = Field.Replace(Selected, text, StringComparison.Ordinal);
            return Task.FromResult(true);
        }
    }

    [Fact]
    public async Task SelectAllOverridesExistingSelectionAndCurrentLineSetting()
    {
        var input = new Input("Yesterday I go to school.", "school");
        var capture = await TextSelection.CaptureAsync(input, NoSelectionScope.CurrentLine, selectAll: true);
        Assert.Equal(new CapturedText(input.Field, true, true), capture);
        Assert.Equal(new[] { "all", "copy" }, input.Operations);
    }

    [Fact]
    public async Task OrdinaryCheckKeepsSelectedRange()
    {
        var input = new Input("before Yesterday I go to school. after", "Yesterday I go to school.");
        var capture = await TextSelection.CaptureAsync(input, NoSelectionScope.WholeField, selectAll: false);
        Assert.Equal(new CapturedText(input.Selected!, false, false), capture);
        Assert.Equal(new[] { "copy" }, input.Operations);
        Assert.True(await TextSelection.ReplaceAsync(input, capture!, "Yesterday I went to school."));
        Assert.Equal("before Yesterday I went to school. after", input.Field);
    }

    [Theory]
    [InlineData(NoSelectionScope.WholeField, true, "all")]
    [InlineData(NoSelectionScope.CurrentLine, false, "line")]
    public async Task OrdinaryCheckKeepsConfiguredFallback(NoSelectionScope scope, bool wholeField, string operation)
    {
        var input = new Input("Yesterday I go to school.");
        var capture = await TextSelection.CaptureAsync(input, scope, selectAll: false);
        Assert.Equal(new CapturedText(input.Field, true, wholeField), capture);
        Assert.Equal(new[] { "copy", operation, "copy" }, input.Operations);
    }

    [Fact]
    public async Task ExplicitSelectAllDoesNotFallBackToCurrentLine()
    {
        var input = new Input("first\nlast") { SupportsSelectAll = false };
        Assert.Null(await TextSelection.CaptureAsync(input, NoSelectionScope.CurrentLine, selectAll: true));
        Assert.Equal(new[] { "all", "copy" }, input.Operations);
    }

    [Fact]
    public async Task WholeFieldIsReselectedAndReplacedWithoutAppending()
    {
        var input = new Input("  Yesterday I go to school.  ");
        var capture = await TextSelection.CaptureAsync(input, NoSelectionScope.WholeField, selectAll: true);
        input.Selected = null; // the host dropped its selection when the card took focus
        input.Operations.Clear();
        Assert.True(await TextSelection.ReplaceAsync(input, capture!, "Yesterday I went to school."));
        Assert.Equal("Yesterday I went to school.", input.Field);
        Assert.Equal(new[] { "all", "copy", "paste" }, input.Operations);
    }

    [Fact]
    public async Task ChangedFieldIsNeverOverwritten()
    {
        var input = new Input("original");
        var capture = new CapturedText(input.Field, true, true);
        input.Field = "original plus new typing";
        Assert.False(await TextSelection.ReplaceAsync(input, capture, "replacement"));
        Assert.Equal("original plus new typing", input.Field);
        Assert.DoesNotContain("paste", input.Operations);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("different selection")]
    [InlineData(" original ")]
    public async Task LostOrChangedSelectionIsNeverAppendedOrExpanded(string? selected)
    {
        var input = new Input("original and more", selected);
        Assert.False(await TextSelection.ReplaceAsync(input, new CapturedText("original", false, false), "replacement"));
        Assert.Equal(new[] { "copy" }, input.Operations);
    }

    [Fact]
    public async Task FocusChangeStopsCaptureAndReplacement()
    {
        var inactive = new Input("original") { IsTargetActive = false };
        Assert.Null(await TextSelection.CaptureAsync(inactive, NoSelectionScope.WholeField, true));
        Assert.False(await TextSelection.ReplaceAsync(inactive, new CapturedText("original", true, true), "replacement"));
        Assert.Empty(inactive.Operations);

        var duringSelect = new Input("original") { LeaveAfterSelect = true };
        Assert.Null(await TextSelection.CaptureAsync(duringSelect, NoSelectionScope.WholeField, true));
        Assert.Equal(new[] { "all" }, duringSelect.Operations);

        var duringCopy = new Input("original", "original") { LeaveAfterCopy = true };
        Assert.False(await TextSelection.ReplaceAsync(duringCopy, new CapturedText("original", false, false), "replacement"));
        Assert.Equal(new[] { "copy" }, duringCopy.Operations);
    }
}
