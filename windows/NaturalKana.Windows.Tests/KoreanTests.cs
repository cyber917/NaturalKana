using System.Text.Json.Nodes;
using NaturalKana.Windows.Core;
using Xunit;

namespace NaturalKana.Windows.Tests;

// Mirrors KoreanTests.swift.
public class KoreanTests
{
    static readonly SuggestionLanguage Korean = new("korean");
    static AppSettings Settings => new() { Language = Korean };

    [Theory]
    [InlineData("저는 어제 친구가 만났어요."), InlineData("내일 meeting이 있어서 늦어요"), InlineData("ㅋㅋ 진짜 웃기다"), InlineData("내일 会議가 있어요"), InlineData("제 iPhone이 고장 났어요")]
    public void LearnerDraftsPass(string text) => Assert.True(Languages.AcceptsDraft(Korean, text));

    [Theory]
    [InlineData("今日は天気がいいですね"), InlineData("I have a meeting tomorrow"), InlineData("我明天有工作"), InlineData("이 문장을 영어로 번역해 주세요"), InlineData("ㅋㅋㅋㅋ")]
    public void OtherDraftsRejected(string text) => Assert.False(Languages.AcceptsDraft(Korean, text));

    [Fact]
    public void CandidatesStayInHangul()
    {
        Assert.True(Languages.AcceptsCandidate(Korean, "저는 어제 친구를 만났어요.", "저는 어제 친구가 만났어요."));
        Assert.True(Languages.AcceptsCandidate(Korean, "제 iPhone이 고장 났어요.", "제 iPhone이 고장 났어"));
        Assert.False(Languages.AcceptsCandidate(Korean, "내일 meeting이 있어요.", "내일 meeting이 있어요"));
        Assert.False(Languages.AcceptsCandidate(Korean, "내일 会議가 있어요.", "내일 会議가 있어요"));
        Assert.False(Languages.AcceptsCandidate(Korean, "明日は会議があります。", "내일 회의"));
    }

    [Fact]
    public void CompatibilityJamoAreShownAsTyped()
    {
        var json = """{"assessment":"rewrite","suggestions":[{"text":"이 영화 진짜 꿀잼이야 ㅋㅋ","register":"casual"},{"text":"이 영화 진짜 재미있어요.","register":"polite"}]}""";
        var items = ResponseValidator.Inspect(json, "이 영화 정말 재미있어요 ㅋㅋ", Settings).Suggestions;
        Assert.Equal(["이 영화 진짜 꿀잼이야 ㅋㅋ", "이 영화 진짜 재미있어요."], items.Select(s => s.Text));
        Assert.Equal("반말", Languages.RegisterTitle(Korean, Register.Casual));
        Assert.Equal("존댓말", Languages.RegisterTitle(Korean, Register.Polite));
    }

    [Fact]
    public void AutomaticLanguageFindsKorean()
    {
        Assert.Equal(Korean, Languages.Detect("저는 어제 친구가 만났어요.", SuggestionLanguage.Japanese));
        Assert.Equal(Korean, Languages.Detect("내일 meeting이 있어서 늦어요", SuggestionLanguage.English));
        Assert.Equal(SuggestionLanguage.Japanese, Languages.Detect("今何にしていますか", Korean));
        Assert.Equal(SuggestionLanguage.Chinese, Languages.Detect("我明天有工作，所以请等一点我", Korean));
    }

    [Fact]
    public void PromptIsKorean()
    {
        var prompt = PromptBuilder.Make("저는 어제 친구가 만났어요.", Settings);
        Assert.StartsWith("You are a Korean phrasing assistant", prompt.System);
        Assert.Equal("korean", (string?)JsonNode.Parse(prompt.User)!["language"]);
    }
}
