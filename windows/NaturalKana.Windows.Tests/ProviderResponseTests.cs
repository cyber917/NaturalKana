using System.Net;
using System.Net.Http;
using System.Text;
using NaturalKana.Windows.Core;
using Xunit;

namespace NaturalKana.Windows.Tests;

public class ProviderResponseTests
{
    sealed class Stub(HttpStatusCode status, string body) : HttpMessageHandler
    {
        public HttpRequestMessage? Request;
        public string? Sent;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancel)
        {
            Request = request;
            Sent = await request.Content!.ReadAsStringAsync(cancel);
            return new HttpResponseMessage(status) { Content = new StringContent(body, Encoding.UTF8, "application/json") };
        }
    }

    static readonly Prompt Prompt = new("s", "u", 5);

    static async Task<(string json, Stub stub)> Run(HttpStatusCode status, string body, ProviderKind kind = ProviderKind.Qwen)
    {
        var stub = new Stub(status, body);
        var config = Providers.Default(kind);
        config.Model = "m";
        var json = await new Provider(kind, config, "secret-key", new HttpClient(stub)).SuggestAsync(Prompt, default);
        return (json, stub);
    }

    static async Task<SuggestionException> Fail(HttpStatusCode status, string body, ProviderKind kind = ProviderKind.Qwen) =>
        await Assert.ThrowsAsync<SuggestionException>(() => Run(status, body, kind));

    [Fact]
    public async Task ChatCompletionContentIsReturnedAndFenceStripped()
    {
        var content = "```json\n{\"assessment\":\"natural\",\"suggestions\":[]}\n```";
        var body = "{\"choices\":[{\"finish_reason\":\"stop\",\"message\":{\"content\":" + System.Text.Json.JsonSerializer.Serialize(content) + "}}]}";
        var (json, stub) = await Run(HttpStatusCode.OK, body);
        Assert.Equal("{\"assessment\":\"natural\",\"suggestions\":[]}", json);
        Assert.Equal("https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions", stub.Request!.RequestUri!.ToString());
        Assert.Equal("Bearer secret-key", stub.Request.Headers.Authorization!.ToString());
    }

    [Fact]
    public async Task ClaudeUsesMessagesHeadersAndTextBlocks()
    {
        var (json, stub) = await Run(HttpStatusCode.OK, """{"stop_reason":"end_turn","content":[{"type":"text","text":"{\"suggestions\":[]}"}]}""", ProviderKind.Claude);
        Assert.Equal("{\"suggestions\":[]}", json);
        Assert.Equal("secret-key", stub.Request!.Headers.GetValues("x-api-key").Single());
        Assert.EndsWith("/v1/messages", stub.Request.RequestUri!.ToString());
    }

    [Fact]
    public async Task TruncatedAndRefusedAreReported()
    {
        Assert.Equal(Diagnostic.Truncated, (await Fail(HttpStatusCode.OK, """{"choices":[{"finish_reason":"length","message":{"content":"{"}}]}""")).Kind);
        Assert.Equal(Diagnostic.Refused, (await Fail(HttpStatusCode.OK, """{"choices":[{"finish_reason":"stop","message":{"content":"x","refusal":"no"}}]}""")).Kind);
        Assert.Equal(Diagnostic.InvalidResponse, (await Fail(HttpStatusCode.OK, "not json")).Kind);
    }

    [Theory]
    [InlineData("insufficient_quota", Diagnostic.ProviderQuota)]
    [InlineData("model_not_found", Diagnostic.ModelUnavailable)]
    [InlineData("unsupported_parameter", Diagnostic.UnsupportedParameter)]
    public async Task KnownErrorCodesWithoutLeakingBodies(string code, Diagnostic expected)
    {
        var error = await Fail(HttpStatusCode.BadRequest, "{\"error\":{\"code\":\"" + code + "\",\"message\":\"SECRET\"}}");
        Assert.Equal(expected, error.Kind);
        Assert.DoesNotContain("SECRET", error.Message);
    }

    [Fact]
    public async Task HttpStatusMessages()
    {
        var error = await Fail(HttpStatusCode.Unauthorized, "{}");
        Assert.Equal(401, error.Status);
        Assert.Contains("HTTP 401", error.Message);
    }
}
