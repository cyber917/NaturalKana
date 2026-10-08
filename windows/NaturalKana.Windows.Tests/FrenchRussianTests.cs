using System.Text.Json;
using System.Text.Json.Nodes;
using NaturalKana.Windows.Core;
using Xunit;

namespace NaturalKana.Windows.Tests;

// Mirrors FrenchRussianTests.swift.
public class FrenchRussianTests
{
    static readonly SuggestionLanguage French = new("french");
    static readonly SuggestionLanguage Russian = new("russian");

    [Fact]
    public void LearnerDraftsAndCandidates()
    {
        foreach (var text in new[] { "Je suis aller au magasin hier.", "Tu peux me dire c'est où la gare ?", "Je voudrais un café.", "Merci !", "Ça va ?", "J’aime bien cette idée." })
            Assert.True(Languages.AcceptsDraft(French, text));
        foreach (var text in new[] { "I have a meeting tomorrow.", "Я завтра работаю.", "Traduis cette phrase en anglais." })
        {
            Assert.False(Languages.AcceptsDraft(French, text));
            Assert.False(Languages.AcceptsCandidate(French, text, "Je travaille demain."));
        }
        Assert.True(Languages.AcceptsCandidate(French, "Tu pourrais me dire où se trouve la gare ?", "Tu peux me dire c'est où la gare ?"));
        Assert.True(Languages.AcceptsCandidate(French, "Je voudrais un cafe\u0301.", "Je voudrais un cafe."));
        Assert.False(Languages.AcceptsCandidate(French, "Je voudrais 明日.", "Je voudrais 明日."));
        Assert.True(Languages.AcceptsDraft(Russian, "У меня завтра meeting, поэтому не смогу прийти."));
        Assert.True(Languages.AcceptsCandidate(Russian, "У меня завтра встреча, поэтому не смогу прийти.", "У меня завтра meeting."));
        Assert.True(Languages.AcceptsCandidate(Russian, "Мой iPhone не работает.", "Мой iPhone сломан."));
        Assert.True(Languages.AcceptsCandidate(Russian, "Всё хорошо.", "Все хорошо."));
        foreach (var text in new[] { "У меня завтра meeting.", "今日は会議です。", "Переведи это предложение на английский." })
            Assert.False(Languages.AcceptsCandidate(Russian, text, "У меня завтра meeting."));
        Assert.False(Languages.AcceptsDraft(Russian, "Je travaille demain."));
    }

    [Fact]
    public void AutomaticLanguageAndSavedSettings()
    {
        Assert.Equal(French, Languages.Detect("Je travaille demain.", SuggestionLanguage.English));
        Assert.Equal(Russian, Languages.Detect("Я завтра работаю.", French));
        Assert.Equal(SuggestionLanguage.English, Languages.Detect("I have a meeting tomorrow.", French));
        foreach (var language in new[] { French, Russian })
        {
            Assert.Equal(language, JsonSerializer.Deserialize<SuggestionLanguage>(JsonSerializer.Serialize(language)));
            var prompt = PromptBuilder.Make(Languages.TestDraft(language), new AppSettings { Language = language });
            Assert.Contains($"Output only {Languages.PromptName(language)} candidates", prompt.System);
            Assert.Contains("REVIEW NOTE", prompt.System);
            Assert.Equal(language.Id, (string?)JsonNode.Parse(prompt.User)!["language"]);
        }
    }

    [Theory]
    [InlineData("french", "Je voudrais un cafe.", "Je voudrais un café.")]
    [InlineData("russian", "Я завтра работать.", "Я завтра работаю.")]
    public void ResponsePreservesAccentsAndCyrillic(string id, string draft, string candidate)
    {
        var json = JsonSerializer.Serialize(new { assessment = "rewrite", suggestions = new[] { new { text = candidate, register = "polite" } } });
        var items = ResponseValidator.Inspect(json, draft, new AppSettings { Language = new(id) }).Suggestions;
        Assert.Equal([candidate], items.Select(s => s.Text));
    }
}
