using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using NaturalKana.Windows.Core;
using Xunit;

namespace NaturalKana.Windows.Tests;

// Mirrors NaturalSuggestCore/Tests/NaturalSuggestCoreTests/DialectTests.swift.
public class DialectTests
{
    static AppSettings Kansai => new() { Dialect = Dialect.Kansai };
    const string Mixed = """{"assessment":"rewrite","suggestions":[{"text":"今何してるん？","register":"kansai"},{"text":"今何してますか？","register":"polite"},{"text":"今何してる？","register":"casual"}]}""";
    const string Draft = "今何にしていますか";

    static IReadOnlyList<Suggestion> Validate(string json, AppSettings settings, string draft = Draft) =>
        ResponseValidator.Inspect(json, draft, settings).Suggestions;

    [Fact]
    public void OldSettingsDefaultToDialectOff()
    {
        var options = new JsonSerializerOptions { Converters = { new JsonStringEnumConverter() } };
        var legacy = JsonSerializer.Deserialize<AppSettings>("""{"Consent":true,"Provider":"DeepSeek","SlangLevel":"Off"}""", options)!;
        Assert.Equal(Dialect.Off, legacy.Dialect);
        Assert.Equal(ProviderKind.DeepSeek, legacy.Provider);
        var restored = JsonSerializer.Deserialize<AppSettings>(JsonSerializer.Serialize(Kansai, options), options)!;
        Assert.Equal(Dialect.Kansai, restored.Dialect);
    }

    [Fact]
    public void DialectAppliesToJapaneseOnly()
    {
        Assert.Equal(Dialect.Kansai, Kansai.ActiveDialect);
        Assert.Equal(Dialect.Off, new AppSettings { Dialect = Dialect.Kansai, Language = SuggestionLanguage.English }.ActiveDialect);
        Assert.Equal(Dialect.Off, new AppSettings().ActiveDialect);
    }

    [Theory]
    [InlineData("それくれんねんやった 俺いかんかったのに"), InlineData("明日雨やったら行かへん"), InlineData("めっちゃええやん"), InlineData("知らんけど")]
    public void KansaiDraftsPass(string text) => Assert.True(Languages.AcceptsDraft(SuggestionLanguage.Japanese, text));

    [Theory]
    [InlineData("今何してるん？"), InlineData("昨日友達に会ってん。"), InlineData("今日はええ天気やね。"), InlineData("それくれるんやったら、俺行かへんかったのに。"), InlineData("行かはりますか？")]
    public void KansaiCandidatesPass(string text) => Assert.True(Languages.AcceptsCandidate(SuggestionLanguage.Japanese, text, Draft));

    [Fact]
    public void ValidatorGroupsKansaiAfterStandardRegisters()
    {
        var items = Validate(Mixed, Kansai);
        Assert.Equal([Register.Casual, Register.Polite, Register.Kansai], items.Select(s => s.Register));
        Assert.Equal(JapaneseText.Nfkc("今何してるん？"), items[^1].Text);
    }

    [Fact]
    public void KansaiRowsAreDroppedUnlessSelected()
    {
        Assert.Equal([Register.Casual, Register.Polite], Validate(Mixed, new AppSettings()).Select(s => s.Register));
        var english = new AppSettings { Dialect = Dialect.Kansai, Language = SuggestionLanguage.English };
        var report = ResponseValidator.Inspect("""{"assessment":"rewrite","suggestions":[{"text":"今何してるん？","register":"kansai"}]}""", "What are you doing now", english);
        Assert.Empty(report.Suggestions);
        Assert.Equal(1, report.ReceivedCount);
    }

    [Fact]
    public void RegisterPreferenceDoesNotHideTheDialectGroup()
    {
        var casual = Kansai; casual.RegisterPreference = RegisterPreference.FriendsCasual;
        Assert.Equal([Register.Casual, Register.Kansai], Validate(Mixed, casual).Select(s => s.Register));
        var polite = Kansai; polite.RegisterPreference = RegisterPreference.PoliteCasual;
        Assert.Equal([Register.Polite, Register.Kansai], Validate(Mixed, polite).Select(s => s.Register));
    }

    [Fact]
    public void NaturalStandardDraftCanStillShowKansai()
    {
        var report = ResponseValidator.Inspect("""{"assessment":"rewrite","suggestions":[{"text":"今日はええ天気やね。","register":"kansai"}]}""", "今日は天気がいいですね", Kansai);
        Assert.Equal([Register.Kansai], report.Suggestions.Select(s => s.Register));
        Assert.Null(report.EmptyMessage);
    }

    [Fact]
    public void PromptCarriesTheDialectSetting()
    {
        var on = PromptBuilder.Make(Draft, Kansai);
        Assert.Equal("kansai", (string?)JsonNode.Parse(on.User)!["dialect"]);
        Assert.Equal([Register.Casual, Register.Polite, Register.Kansai], on.Registers!.AsEnumerable());
        Assert.Contains("dialect=kansai", on.System);
        Assert.Contains("Regional dialects are not errors", on.System);
        var off = PromptBuilder.Make(Draft, new AppSettings());
        Assert.Equal("off", (string?)JsonNode.Parse(off.User)!["dialect"]);
        Assert.Equal([Register.Casual, Register.Polite], off.Registers!.AsEnumerable());
        var english = PromptBuilder.Make("I go home.", new AppSettings { Dialect = Dialect.Kansai, Language = SuggestionLanguage.English });
        Assert.Equal("off", (string?)JsonNode.Parse(english.User)!["dialect"]);
    }

    [Fact]
    public void SchemaAllowsKansaiOnlyWhenRequested()
    {
        static IEnumerable<string> Registers(JsonObject schema) =>
            schema["properties"]!["suggestions"]!["items"]!["properties"]!["register"]!["enum"]!.AsArray().Select(n => (string)n!);
        Assert.Equal(["casual", "polite"], Registers(Provider.Schema(5)));
        Assert.Equal(["casual", "polite", "kansai"], Registers(Provider.Schema(5, [Register.Casual, Register.Polite, Register.Kansai])));
        var config = new ProviderConfig { BaseUrl = "https://example.com/v1", ResponseMode = JsonResponseMode.Schema };
        var body = new Provider(ProviderKind.Custom, config, "k").Body(PromptBuilder.Make(Draft, Kansai), "m");
        Assert.Equal(["casual", "polite", "kansai"], Registers(body["response_format"]!["json_schema"]!["schema"]!.AsObject()));
    }

    [Fact]
    public void GroupTitle()
    {
        Assert.Equal("関西弁", Languages.RegisterTitle(SuggestionLanguage.Japanese, Register.Kansai));
        Assert.Equal("口语", Languages.RegisterTitle(SuggestionLanguage.Japanese, Register.Casual));
    }
}
