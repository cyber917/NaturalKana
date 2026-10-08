using System.IO;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using NaturalKana.Windows.Core;
using NaturalKana.Windows.Win;
using Xunit;

namespace NaturalKana.Windows.Tests;

// Mirrors InterfaceLanguageTests.swift. Tests never change UIText.Language (xUnit runs classes in parallel).
public class InterfaceLanguageTests
{
    static string AppFolder([CallerFilePath] string path = "") =>
        Path.Combine(Path.GetDirectoryName(path)!, "..", "NaturalKana.Windows");

    /// Every UIText.T("…") literal, Chinese XAML text and translated shortcut name in the Windows app.
    static Dictionary<string, string> SourceKeys()
    {
        var keys = new Dictionary<string, string>();
        var literal = new Regex(@"UIText\.T\(""((?:[^""\\]|\\.)*)""");
        foreach (var file in Directory.EnumerateFiles(AppFolder(), "*.cs", SearchOption.AllDirectories))
            foreach (Match m in literal.Matches(File.ReadAllText(file)))
                keys.TryAdd(Regex.Unescape(m.Groups[1].Value), Path.GetFileName(file));
        var cjk = new Regex(@"[぀-ヿ㐀-鿿]");
        foreach (var file in Directory.EnumerateFiles(AppFolder(), "*.xaml", SearchOption.AllDirectories))
        {
            var xaml = File.ReadAllText(file);
            foreach (Match m in Regex.Matches(xaml, @"\b(?:Text|Content|Header|ToolTip|Title)=""([^""]*)"""))
                if (cjk.IsMatch(m.Groups[1].Value)) keys.TryAdd(m.Groups[1].Value, Path.GetFileName(file));
            foreach (Match m in Regex.Matches(xaml, @">([^<>]*[㐀-鿿][^<>]*)<")) keys.TryAdd(m.Groups[1].Value, Path.GetFileName(file));
        }
        foreach (var name in HotkeyHost.CommonShortcutNames) keys.TryAdd(name, "Hotkey.cs");
        return keys;
    }

    [Fact]
    public void EveryInterfaceStringHasEnglishAndJapanese()
    {
        var keys = SourceKeys();
        Assert.True(keys.Count > 100);
        var missing = keys.Where(k => !UIText.Entries.TryGetValue(k.Key, out var e)
            || string.IsNullOrEmpty(e.GetValueOrDefault("en")) || string.IsNullOrEmpty(e.GetValueOrDefault("ja")))
            .Select(k => $"{k.Key} ({k.Value})").ToList();
        Assert.Empty(missing);
    }

    [Fact]
    public void TranslateFillsPlaceholdersInOrderAndFallsBackToChinese()
    {
        Assert.Equal("Max suggestions: 5", UIText.Translate("建议上限：%@ 条", InterfaceLanguage.English, "5"));
        Assert.Equal("候補の上限：5 件", UIText.Translate("建议上限：%@ 条", InterfaceLanguage.Japanese, "5"));
        Assert.Equal("建议上限：5 条", UIText.Translate("建议上限：%@ 条", InterfaceLanguage.Chinese, "5"));
        Assert.Equal("没有这一条：x", UIText.Translate("没有这一条：%@", InterfaceLanguage.English, "x"));
        Assert.Equal("Deleted “%@”.", UIText.Translate("已删除“%@”。", InterfaceLanguage.English, "%@"));
        Assert.Equal("Save", UIText.Translate("保存", InterfaceLanguage.English));
    }

    [Fact]
    public void SystemLanguageFollowsTheCulture()
    {
        Assert.Equal(InterfaceLanguage.Japanese, UIText.Resolve(InterfaceLanguage.System, new System.Globalization.CultureInfo("ja-JP")));
        Assert.Equal(InterfaceLanguage.Chinese, UIText.Resolve(InterfaceLanguage.System, new System.Globalization.CultureInfo("zh-CN")));
        Assert.Equal(InterfaceLanguage.English, UIText.Resolve(InterfaceLanguage.System, new System.Globalization.CultureInfo("fr-FR")));
        Assert.Equal(InterfaceLanguage.English, UIText.Resolve(InterfaceLanguage.English, new System.Globalization.CultureInfo("ja-JP")));
        Assert.Equal("日本語", UIText.Title(InterfaceLanguage.Japanese));
    }

    [Fact]
    public void SettingsKeepInterfaceAndAutoLanguage()
    {
        var options = new JsonSerializerOptions { Converters = { new JsonStringEnumConverter() } };
        var legacy = JsonSerializer.Deserialize<AppSettings>("""{"Consent":true}""", options)!;
        Assert.Equal(InterfaceLanguage.System, legacy.Interface);
        Assert.False(legacy.AutoLanguage);
        var saved = new AppSettings { Interface = InterfaceLanguage.Japanese, AutoLanguage = true };
        var restored = JsonSerializer.Deserialize<AppSettings>(JsonSerializer.Serialize(saved, options), options)!;
        Assert.Equal(InterfaceLanguage.Japanese, restored.Interface);
        Assert.True(restored.AutoLanguage);
    }
}

// Mirrors AutoLanguageTests in InterfaceLanguageTests.swift.
public class AutoLanguageTests
{
    [Theory]
    [InlineData("今何にしていますか", SuggestionLanguage.Chinese, SuggestionLanguage.Japanese)]
    [InlineData("あとでmeetingがあるから、少し待って。", SuggestionLanguage.English, SuggestionLanguage.Japanese)]
    [InlineData("我明天有工作，所以请等一点我", SuggestionLanguage.Japanese, SuggestionLanguage.Chinese)]
    [InlineData("我昨天在コンビニ买了饮料", SuggestionLanguage.Japanese, SuggestionLanguage.Chinese)]
    [InlineData("我明天要meeting", SuggestionLanguage.English, SuggestionLanguage.Chinese)]
    [InlineData("Yesterday I go to school.", SuggestionLanguage.Japanese, SuggestionLanguage.English)]
    [InlineData("I need to 预约 a table for two.", SuggestionLanguage.Chinese, SuggestionLanguage.English)]
    [InlineData("東京駅到着", SuggestionLanguage.Chinese, SuggestionLanguage.Chinese)]
    public void Detects(string text, SuggestionLanguage primary, SuggestionLanguage expected) =>
        Assert.Equal(expected, Languages.Detect(text, primary));

    [Fact]
    public void KanjiOnlyTextIsNotGuessedAsChineseForJapaneseUsers()
    {
        Assert.Null(Languages.Detect("東京駅到着", SuggestionLanguage.Japanese));
        Assert.Null(Languages.Detect("🙂🙂", SuggestionLanguage.Japanese));
    }

    [Fact]
    public void SettingsResolveOnlyWhenAutomatic()
    {
        var settings = new AppSettings { Language = SuggestionLanguage.Japanese, Dialect = Dialect.Kansai };
        Assert.Same(settings, settings.ResolvingLanguage("我明天有工作，所以请等一点我"));
        settings.AutoLanguage = true;
        var chinese = settings.ResolvingLanguage("我明天有工作，所以请等一点我")!;
        Assert.Equal(SuggestionLanguage.Chinese, chinese.Language);
        Assert.Equal(Dialect.Off, chinese.ActiveDialect);
        Assert.Equal(SuggestionLanguage.Japanese, settings.Language); // the saved settings are untouched
        Assert.Same(settings, settings.ResolvingLanguage("今何にしていますか"));
        Assert.Null(settings.ResolvingLanguage("東京駅到着"));
        Assert.StartsWith("You are a Chinese phrasing assistant", PromptBuilder.Make("我明天有工作，所以请等一点我", chinese).System);
    }

    [Fact]
    public void AutoModeUsesTheDetectedLanguage()
    {
        static FieldSnapshot Field(string before) => new("1.2", IntPtr.Zero, before, "", default, false);
        var settings = new AppSettings { Language = SuggestionLanguage.Japanese, AutoLanguage = true, AutoMode = true, Consent = true };
        Assert.True(AutoWatcher.Eligible(Field("我明天有工作，所以请等一点我"), settings));
        Assert.False(AutoWatcher.Eligible(Field("我明天有工作，所以请等一点w"), settings));
        Assert.True(AutoWatcher.Eligible(Field("Yesterday I go to school."), settings));
    }
}
