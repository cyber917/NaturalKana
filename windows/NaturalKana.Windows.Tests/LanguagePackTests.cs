using System.Text.Json;
using System.Text.Json.Serialization;
using NaturalKana.Windows.Core;
using Xunit;

namespace NaturalKana.Windows.Tests;

// Mirrors LanguagePackTests.swift.
public class LanguagePackTests
{
    [Fact]
    public void EveryBundledPackIsComplete()
    {
        Assert.Equal(["japanese", "english", "chinese"], LanguagePack.All.Take(3).Select(p => p.Id));
        foreach (var pack in LanguagePack.All)
        {
            Assert.Contains("maximum_suggestions", pack.Prompt);
            Assert.True(pack.RegisterTitles.ContainsKey("casual") && pack.RegisterTitles.ContainsKey("polite"), pack.Id);
            Assert.True(pack.Rules != "generic" || pack.Generic is not null, pack.Id);
            Assert.True(UIText.Entries.ContainsKey(pack.Title), pack.Id);
            Assert.True(Languages.AcceptsDraft(new SuggestionLanguage(pack.Id), pack.TestDraft), pack.Id);
        }
        Assert.NotEmpty(SuggestionLanguage.Japanese.Pack.Lexicon);
        Assert.Empty(SuggestionLanguage.English.Pack.Lexicon);
        Assert.StartsWith("You are a Japanese phrasing assistant", SuggestionLanguage.Japanese.Pack.Prompt);
    }

    [Theory]
    [InlineData("\"Japanese\"", "japanese"), InlineData("\"English\"", "english"), InlineData("\"Chinese\"", "chinese"),
     InlineData("\"chinese\"", "chinese"), InlineData("\"Klingon\"", "japanese"), InlineData("3", "japanese")]
    public void SavedLanguagesStillLoad(string saved, string expected)
    {
        var options = new JsonSerializerOptions { Converters = { new JsonStringEnumConverter() } };
        var settings = JsonSerializer.Deserialize<AppSettings>($$"""{ "Language": {{saved}} }""", options)!;
        Assert.Equal(expected, settings.Language.Id);
        Assert.Contains($"\"Language\": \"{expected}\"", JsonSerializer.Serialize(settings, new JsonSerializerOptions(options) { WriteIndented = true }));
    }

    static readonly LanguagePack.GenericRules Hangul = new() { Letters = "[\\uAC00-\\uD7A3\\u1100-\\u11FF\\u3130-\\u318F]", Forbidden = "[\\u3040-\\u30FF\\u4E00-\\u9FFF]", LatinAllowlist = ["OK"], Denied = ["번역"] };
    static readonly LanguagePack.GenericRules Cyrillic = new() { Letters = "[\\u0400-\\u04FF]", LatinAllowlist = ["OK"] };
    static readonly LanguagePack.GenericRules Latin = new() { Letters = "[A-Za-z\\u00C0-\\u024F]", Forbidden = "[\\u0400-\\u04FF\\u3040-\\u30FF\\u4E00-\\u9FFF]" };

    [Fact]
    public void GenericDraftsAllowShortForeignWords()
    {
        Assert.True(GenericText.IsDraft(Hangul, "내일 회의가 있어서 못 가요"));
        Assert.True(GenericText.IsDraft(Hangul, "내일 meeting이 있어요"));
        Assert.False(GenericText.IsDraft(Hangul, "I have a meeting tomorrow"));
        Assert.False(GenericText.IsDraft(Hangul, "今日は天気がいいですね"));
        Assert.False(GenericText.IsDraft(Hangul, "이 문장을 번역해 주세요"));
        Assert.True(GenericText.IsDraft(Cyrillic, "Я завтра работаю"));
        Assert.False(GenericText.IsDraft(Cyrillic, "Je travaille demain"));
        Assert.True(GenericText.IsDraft(Latin, "Je suis très fatigué aujourd'hui"));
        Assert.False(GenericText.IsDraft(Latin, "Я завтра работаю"));
        Assert.False(GenericText.IsDraft(null, "내일 회의가 있어요"));
    }

    [Fact]
    public void GenericCandidatesStayInTheLanguage()
    {
        Assert.True(GenericText.AcceptsCandidate(Hangul, "내일 회의가 있어요.", "내일 meeting이 있어요"));
        Assert.False(GenericText.AcceptsCandidate(Hangul, "내일 meeting이 있어요.", "내일 meeting이 있어요"));
        Assert.True(GenericText.AcceptsCandidate(Hangul, "제 iPhone이 고장 났어요.", "제 iPhone이 고장 났어"));
        Assert.True(GenericText.AcceptsCandidate(Hangul, "OK, 알겠어요.", "알겠어"));
        Assert.False(GenericText.AcceptsCandidate(Hangul, "明日は会議があります。", "내일 회의"));
        Assert.False(GenericText.AcceptsCandidate(Hangul, "내일 会議가 있어요", "내일 회의"));
        Assert.True(GenericText.AcceptsCandidate(Cyrillic, "Я завтра работаю.", "Я завтра работать"));
        Assert.True(GenericText.AcceptsCandidate(Latin, "Je suis très fatiguée aujourd'hui.", "Je suis tres fatigue"));
        Assert.False(GenericText.AcceptsCandidate(Latin, "Я завтра работаю.", "Je travaille"));
    }
}
