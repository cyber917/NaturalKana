using System.Windows.Input;
using NaturalKana.Windows.Core;
using NaturalKana.Windows.Win;
using Xunit;

namespace NaturalKana.Windows.Tests;

public class HotkeyTests
{
    [Theory]
    [InlineData("Ctrl+Alt+J"), InlineData("Ctrl+Shift+Space"), InlineData("Alt+Shift+J"), InlineData("Win+Alt+K"), InlineData("Ctrl+D2"), InlineData("Escape")]
    public void ValidCombinations(string text) => Assert.NotNull(HotkeyHost.Parse(text));

    [Theory]
    [InlineData("J"), InlineData("Shift+J"), InlineData("Ctrl+Alt"), InlineData("Ctrl+J+K"), InlineData("Ctrl+NotAKey"), InlineData("")]
    public void InvalidCombinations(string text) => Assert.Null(HotkeyHost.Parse(text));

    [Fact]
    public void RecorderFormat()
    {
        Assert.Equal("Ctrl+Alt+J", HotkeyHost.Format(ModifierKeys.Control | ModifierKeys.Alt, Key.J));
        Assert.Equal("Ctrl+Shift+Space", HotkeyHost.Format(ModifierKeys.Control | ModifierKeys.Shift, Key.Space));
        Assert.Null(HotkeyHost.Format(ModifierKeys.Shift, Key.J));            // needs Ctrl/Alt/Win
        Assert.Null(HotkeyHost.Format(ModifierKeys.Control, Key.LeftCtrl));   // modifier alone
        Assert.Equal(HotkeyHost.Parse("Ctrl+Alt+J"), HotkeyHost.Parse(HotkeyHost.Format(ModifierKeys.Control | ModifierKeys.Alt, Key.J)!));
    }
}

public class AutoModeTests
{
    static FieldSnapshot Field(string before, string after = "") => new("1.2", IntPtr.Zero, before, after, default, false);
    static readonly AppSettings Japanese = new() { AutoMode = true, Consent = true };

    [Fact]
    public void TriggersOnlyForAFinishedDraftAtTheEnd()
    {
        Assert.True(AutoWatcher.Eligible(Field("あとでmeetingがあるから"), Japanese));
        Assert.False(AutoWatcher.Eligible(Field("あとでmeetingが", "あるから"), Japanese)); // caret in the middle
        Assert.False(AutoWatcher.Eligible(Field("今日はh"), Japanese));                     // unfinished romaji
        Assert.False(AutoWatcher.Eligible(Field("はい"), Japanese));                          // shorter than minimum
        Assert.False(AutoWatcher.Eligible(Field("我今天很累"), Japanese));                    // not Japanese
        Assert.False(AutoWatcher.Eligible(Field(new string('あ', 201)), Japanese));          // too long
    }

    [Fact]
    public void EnglishModeUsesEnglishGate()
    {
        var english = new AppSettings { AutoMode = true, Consent = true, Language = SuggestionLanguage.English };
        Assert.True(AutoWatcher.Eligible(Field("Yesterday I go to school"), english));
        Assert.False(AutoWatcher.Eligible(Field("今日は仕事があります"), english));
    }

    [Fact]
    public void OldSettingsFilesStillLoad()
    {
        var json = """{ "Consent": true, "Provider": "QwenChina", "Hotkey": "Ctrl+Alt+J" }""";
        var settings = System.Text.Json.JsonSerializer.Deserialize<AppSettings>(json, new System.Text.Json.JsonSerializerOptions { Converters = { new System.Text.Json.Serialization.JsonStringEnumConverter() } })!;
        Assert.Equal(NoSelectionScope.WholeField, settings.NoSelection);
        Assert.False(settings.AutoMode);
        Assert.Equal(SuggestionLanguage.Japanese, settings.Language);
    }
}

public class CommonShortcutTests
{
    [Theory]
    [InlineData("Ctrl+Z"), InlineData("Ctrl+C"), InlineData("Ctrl+V"), InlineData("Ctrl+A"), InlineData("Ctrl+Space")]
    public void EverydayShortcutsAreRejected(string text) => Assert.NotNull(HotkeyHost.CommonShortcutName(text));

    [Theory]
    [InlineData("Ctrl+Alt+J"), InlineData("Ctrl+Shift+Space"), InlineData("Alt+Shift+J")]
    public void DedicatedShortcutsAreAllowed(string text) => Assert.Null(HotkeyHost.CommonShortcutName(text));
}

public class SelectAllShortcutTests
{
    [Fact]
    public void LegacySettingsKeepExistingShortcutAndAddSelectAllDefault()
    {
        var settings = System.Text.Json.JsonSerializer.Deserialize<AppSettings>("""{"Hotkey":"Ctrl+Shift+J"}""")!;
        Assert.Equal("Ctrl+Shift+J", settings.Hotkey);
        Assert.Equal("Ctrl+Alt+K", settings.SelectAllHotkey);
        settings.SelectAllHotkey = "Ctrl+Shift+K";
        var restored = System.Text.Json.JsonSerializer.Deserialize<AppSettings>(System.Text.Json.JsonSerializer.Serialize(settings))!;
        Assert.Equal("Ctrl+Shift+K", restored.SelectAllHotkey);
        Assert.Equal(settings.Hotkey, restored.Hotkey);
    }

    [Fact]
    public void ComparisonsUseKeyCodesNotModifierOrder()
    {
        Assert.True(HotkeyHost.SameCombination("Ctrl+Alt+K", "alt+ctrl+k"));
        Assert.False(HotkeyHost.SameCombination("Ctrl+Alt+J", "Ctrl+Alt+K"));
        Assert.False(HotkeyHost.SameCombination("invalid", "invalid"));
        Assert.False(HotkeyHost.IsUserShortcut("Escape"));
        Assert.False(HotkeyHost.IsUserShortcut("Ctrl+None"));
        Assert.NotNull(HotkeyHost.CommonShortcutName("Shift+Ctrl+Z"));
    }

    [Fact]
    public void NewDefaultDoesNotStealExistingShortcut()
    {
        Assert.Equal(("Ctrl+Alt+K", "Ctrl+Alt+Shift+K"), HotkeyHost.SavedShortcuts("Ctrl+Alt+K", HotkeyPreset.SelectAll));
        Assert.Equal((HotkeyPreset.Default, HotkeyPreset.SelectAll), HotkeyHost.SavedShortcuts("Ctrl+Z", "Escape"));
        Assert.Equal(("Ctrl+Shift+J", "Ctrl+Shift+K"), HotkeyHost.SavedShortcuts("Ctrl+Shift+J", "Ctrl+Shift+K"));
    }
}
