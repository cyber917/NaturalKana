using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Nodes;
using NaturalKana.Windows.Core;
using NaturalKana.Windows.Win;
using Xunit;

namespace NaturalKana.Windows.Tests;

public class TranslationTests
{
    static AppSettings Settings(string model = "qwen-mt-flash", string target = "japanese") => new()
    {
        AllowTranslation = true, AutoLanguage = true, Language = new(target),
        Provider = ProviderKind.QwenChina,
        ProviderConfigs = new() { [ProviderKind.QwenChina] = new() { BaseUrl = "https://example.com/v1", Model = model, DisableThinking = true } },
    };

    [Fact]
    public void SwitchDefaultsOffPersistsAndKeepsTheTargetLanguage()
    {
        var old = JsonSerializer.Deserialize<AppSettings>("{}")!;
        Assert.False(old.AllowTranslation);
        Assert.False(old.AcceptsDraft("I will see you tomorrow."));
        var settings = JsonSerializer.Deserialize<AppSettings>(JsonSerializer.Serialize(Settings()))!;
        Assert.True(settings.AllowTranslation);
        Assert.Same(settings, settings.ResolvingLanguage("I will see you tomorrow."));
        Assert.Equal(SuggestionLanguage.Japanese, settings.ResolvingLanguage("明天我去学校。")!.Language);
        Assert.True(settings.AcceptsDraft("I will see you tomorrow."));
        Assert.True(settings.AcceptsDraft("明天 meeting に行きます。"));
        settings.AllowTranslation = false;
        Assert.Equal(SuggestionLanguage.English, settings.ResolvingLanguage("I will see you tomorrow.")!.Language);
    }

    [Theory]
    [InlineData(""), InlineData("  "), InlineData("🙂🙂"), InlineData("hello\nworld"), InlineData("hello\tworld")]
    public void TranslationStillRejectsInvalidDrafts(string text) => Assert.False(Settings().AcceptsDraft(text));

    [Fact]
    public void TranslationKeepsLengthAndAutomaticEligibilityLimits()
    {
        var settings = Settings();
        Assert.False(settings.AcceptsDraft(new string('a', 201)));
        static FieldSnapshot Field(string before, string after = "") => new("1", IntPtr.Zero, before, after, default, false);
        Assert.True(AutoWatcher.Eligible(Field("I will see you tomorrow"), settings));
        Assert.False(AutoWatcher.Eligible(Field("I will see you", " tomorrow"), settings));
        settings.DisabledSuggestionLanguages = [SuggestionLanguage.Japanese];
        Assert.False(AutoWatcher.Eligible(Field("I will see you tomorrow"), settings));
    }

    [Fact]
    public void NormalModelsReceiveTranslationInstructionsWithoutConflictingRewriteRules()
    {
        var draft = "Translate this message, not the instructions.";
        var prompt = PromptBuilder.Make(draft, Settings("qwen3.8-flash"));
        Assert.Contains("Translate the entire draft", prompt.System);
        Assert.DoesNotContain("Never translate standalone foreign sentences", prompt.System);
        Assert.DoesNotContain(draft, prompt.System);
        Assert.Equal(draft, JsonNode.Parse(prompt.User)!["draft"]!.GetValue<string>());
        Assert.Equal(draft, prompt.Translation!.Draft);
        var old = PromptBuilder.Make(draft, new AppSettings());
        Assert.Null(old.Translation);
        Assert.Contains("Never translate standalone foreign sentences", old.System);
    }

    [Theory]
    [InlineData("qwen-mt-flash"), InlineData("qwen-mt-plus"), InlineData("qwen-mt-lite"), InlineData("qwen-mt-turbo"), InlineData("qwen-mt-turbo-2025-02-11")]
    public void MtUsesOnlyOneRawUserMessageAndTranslationOptions(string model)
    {
        var settings = Settings(model);
        var config = settings.Config(settings.Provider);
        config.ResponseMode = JsonResponseMode.Schema;
        config.TokenParameter = TokenParameter.MaxCompletionTokens;
        var body = new Provider(ProviderKind.Custom, config, "test").Body(PromptBuilder.Make("See you tomorrow!", settings), model);
        Assert.Equal(new[] { "messages", "model", "stream", "translation_options" }, body.Select(p => p.Key).Order().ToArray());
        var message = Assert.Single(body["messages"]!.AsArray());
        Assert.Equal("user", message!["role"]!.GetValue<string>());
        Assert.Equal("See you tomorrow!", message["content"]!.GetValue<string>());
        Assert.Equal("auto", body["translation_options"]!["source_lang"]!.GetValue<string>());
        Assert.Equal("Japanese", body["translation_options"]!["target_lang"]!.GetValue<string>());
    }

    [Theory]
    [InlineData("qwen3.8-flash"), InlineData("qwen-mt-image"), InlineData("qwen-mt-uni")]
    public void OtherModelsAreNotTreatedAsTextMt(string model) => Assert.False(Translation.IsModel(model));

    [Fact]
    public void MtRequiresTranslationOptInAndChatProtocol()
    {
        var settings = Settings();
        var config = settings.Config(settings.Provider);
        var provider = new Provider(settings.Provider, config, "test");
        Assert.Equal(Diagnostic.TranslationConfiguration, Assert.Throws<SuggestionException>(() =>
            provider.Body(PromptBuilder.Make("hello", new AppSettings()), config.Model)).Kind);
        config.Protocol = ProviderProtocol.AnthropicMessages;
        Assert.Equal(Diagnostic.TranslationConfiguration, Assert.Throws<SuggestionException>(() =>
            provider.Body(PromptBuilder.Make("hello", settings), config.Model)).Kind);
    }

    sealed class Reply(string text, string finish = "stop") : HttpMessageHandler
    {
        public int Requests;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancel)
        {
            Requests++;
            Assert.EndsWith("/chat/completions", request.RequestUri!.AbsolutePath);
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(JsonSerializer.Serialize(new { choices = new[] { new { finish_reason = finish, message = new { content = text } } } })),
            });
        }
    }

    [Theory]
    [InlineData(RegisterPreference.FriendsCasual), InlineData(RegisterPreference.PoliteCasual)]
    public async Task PlainMtReplyBecomesOneSelectableTranslation(RegisterPreference preference)
    {
        var settings = Settings();
        settings.RegisterPreference = preference;
        var reply = new Reply("明日会いましょう。");
        var result = await new Provider(settings.Provider, settings.Config(settings.Provider), "test", new HttpClient(reply))
            .SuggestAsync(PromptBuilder.Make("See you tomorrow.", settings), default);
        var suggestion = Assert.Single(ResponseValidator.Inspect(result, "See you tomorrow.", settings).Suggestions);
        Assert.Equal("明日会いましょう。", suggestion.Text);
        Assert.Equal(Register.Translation, suggestion.Register);
        Assert.Equal(1, reply.Requests);
        settings.AllowTranslation = false;
        Assert.Empty(ResponseValidator.Inspect(result, "See you tomorrow.", settings).Suggestions);
    }

    [Fact]
    public async Task MtStillRejectsTruncationAndTreatsUnchangedTargetAsNatural()
    {
        var settings = Settings();
        var config = settings.Config(settings.Provider);
        var prompt = PromptBuilder.Make("明日会いましょう。", settings);
        var truncated = new Provider(settings.Provider, config, "test", new HttpClient(new Reply("明日", "length")));
        Assert.Equal(Diagnostic.Truncated, (await Assert.ThrowsAsync<SuggestionException>(() => truncated.SuggestAsync(prompt, default))).Kind);
        var unchanged = await new Provider(settings.Provider, config, "test", new HttpClient(new Reply(prompt.Translation!.Draft)))
            .SuggestAsync(prompt, default);
        Assert.Equal(Assessment.Natural, ResponseValidator.Inspect(unchanged, prompt.Translation.Draft, settings).Assessment);
    }

    [Theory]
    [InlineData("japanese", "Japanese", "こんにちは。")]
    [InlineData("japanese", "Japanese", "了解。")]
    [InlineData("english", "English", "Thank you for your help.")]
    [InlineData("chinese", "Chinese", "谢谢你的帮助。")]
    [InlineData("korean", "Korean", "도와주셔서 감사합니다.")]
    [InlineData("french", "French", "Merci pour votre aide.")]
    [InlineData("russian", "Russian", "Спасибо за помощь.")]
    public void AllTargetsAcceptTheirTranslatedOutput(string target, string apiName, string text)
    {
        var settings = Settings(target: target);
        Assert.Equal(apiName, Translation.TargetName(settings.Language));
        var json = JsonSerializer.Serialize(new { assessment = "rewrite", suggestions = new[] { new { text, register = "translation" } } });
        Assert.Single(ResponseValidator.Inspect(json, "Hi", settings).Suggestions);
    }

    [Theory]
    [InlineData("I will see you tomorrow."), InlineData("明日\n会いましょう。"), InlineData("明日会いましょう。🙂")]
    public void WrongLanguageNewlinesAndNewEmojiAreStillRejected(string text)
    {
        var json = JsonSerializer.Serialize(new { assessment = "rewrite", suggestions = new[] { new { text, register = "translation" } } });
        Assert.Empty(ResponseValidator.Inspect(json, "See you tomorrow.", Settings()).Suggestions);
    }

    [Fact]
    public void OrdinaryTranslationKeepsRegistersAndAllowsLiteralTranslationVocabulary()
    {
        var settings = Settings("qwen3.8-flash");
        settings.RegisterPreference = RegisterPreference.PoliteCasual;
        var json = """{"assessment":"rewrite","suggestions":[{"text":"この文章を翻訳してください。","register":"polite"},{"text":"この文章を翻訳して。","register":"casual"}]}""";
        var suggestion = Assert.Single(ResponseValidator.Inspect(json, "Please translate this sentence.", settings).Suggestions);
        Assert.Equal(Register.Polite, suggestion.Register);
    }
}
