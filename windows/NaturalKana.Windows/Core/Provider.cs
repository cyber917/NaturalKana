using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace NaturalKana.Windows.Core;

/// Port of CompatibleProvider: OpenAI-compatible Chat Completions and Claude Messages.
public sealed class Provider(ProviderKind kind, ProviderConfig config, string key, HttpClient? client = null)
{
    static readonly HttpClient Http = new(new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false })
    {
        Timeout = TimeSpan.FromSeconds(20),
    };

    internal static JsonObject Schema(int maximumSuggestions) => new()
    {
        ["type"] = "object",
        ["additionalProperties"] = false,
        ["required"] = new JsonArray("assessment", "suggestions"),
        ["properties"] = new JsonObject
        {
            ["assessment"] = new JsonObject { ["type"] = "string", ["enum"] = new JsonArray("natural", "rewrite", "unsupported") },
            ["suggestions"] = new JsonObject
            {
                ["type"] = "array",
                ["maxItems"] = Math.Clamp(maximumSuggestions, 1, 10),
                ["items"] = new JsonObject
                {
                    ["type"] = "object",
                    ["additionalProperties"] = false,
                    ["required"] = new JsonArray("text", "register"),
                    ["properties"] = new JsonObject
                    {
                        ["text"] = new JsonObject { ["type"] = "string" },
                        ["register"] = new JsonObject { ["type"] = "string", ["enum"] = new JsonArray("casual", "polite") },
                    },
                },
            },
        },
    };

    internal JsonObject Body(Prompt prompt, string model)
    {
        var native = config.Protocol == ProviderProtocol.AnthropicMessages;
        var tokenLimit = Math.Max(2048, prompt.MaximumSuggestions * 768);
        var body = new JsonObject { ["model"] = model, ["stream"] = false };
        if (native)
        {
            body["system"] = prompt.System;
            body["messages"] = new JsonArray(new JsonObject { ["role"] = "user", ["content"] = prompt.User });
            body["max_tokens"] = tokenLimit;
            return body;
        }
        body["messages"] = new JsonArray(
            new JsonObject { ["role"] = "system", ["content"] = prompt.System },
            new JsonObject { ["role"] = "user", ["content"] = prompt.User });
        var completionTokens = config.TokenParameter == TokenParameter.MaxCompletionTokens
            || (config.TokenParameter == TokenParameter.Automatic && kind == ProviderKind.OpenAI);
        body[completionTokens ? "max_completion_tokens" : "max_tokens"] = tokenLimit;
        var mode = config.ResponseMode == JsonResponseMode.Automatic
            ? (kind is ProviderKind.OpenAI or ProviderKind.Gemini || Providers.IsQwen(kind) ? JsonResponseMode.Schema
               : kind == ProviderKind.Custom ? JsonResponseMode.Prompt : JsonResponseMode.Object)
            : config.ResponseMode;
        if (mode == JsonResponseMode.Schema)
            body["response_format"] = new JsonObject
            {
                ["type"] = "json_schema",
                ["json_schema"] = new JsonObject { ["name"] = "natural_suggestions", ["strict"] = true, ["schema"] = Schema(prompt.MaximumSuggestions) },
            };
        else if (mode == JsonResponseMode.Object)
            body["response_format"] = new JsonObject { ["type"] = "json_object" };
        if (kind == ProviderKind.OpenAI) body["store"] = false;
        if (Providers.IsQwen(kind) && config.DisableThinking) body["enable_thinking"] = false;
        return body;
    }

    public async Task<string> SuggestAsync(Prompt prompt, CancellationToken cancel)
    {
        if (string.IsNullOrWhiteSpace(key)) throw new SuggestionException(Diagnostic.MissingKey);
        var model = config.Model.Trim();
        if (model.Length == 0) throw new SuggestionException(Diagnostic.Configuration);
        if (model.Any(char.IsWhiteSpace)) throw new SuggestionException(Diagnostic.InvalidModelId);
        var native = config.Protocol == ProviderProtocol.AnthropicMessages;

        using var request = new HttpRequestMessage(HttpMethod.Post, config.Endpoint(native ? "messages" : "chat/completions"));
        if (native)
        {
            request.Headers.Add("x-api-key", key);
            request.Headers.Add("anthropic-version", "2023-06-01");
        }
        else request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + key);
        request.Content = new StringContent(Body(prompt, model).ToJsonString(), Encoding.UTF8, "application/json");

        HttpResponseMessage response;
        string text;
        try
        {
            response = await (client ?? Http).SendAsync(request, cancel);
            text = await response.Content.ReadAsStringAsync(cancel);
        }
        catch (TaskCanceledException) when (!cancel.IsCancellationRequested) { throw new SuggestionException(Diagnostic.Timeout); }
        catch (HttpRequestException) { throw new SuggestionException(Diagnostic.Network); }
        if (text.Length > 131_072) throw new SuggestionException(Diagnostic.InvalidResponse);

        JsonObject? obj = null;
        try { obj = JsonNode.Parse(text) as JsonObject; } catch (JsonException) { }
        var code = (int)response.StatusCode;
        if (code is < 200 or >= 300)
        {
            // Only classify allowlisted codes and parameter names; never expose raw bodies.
            var error = obj?["error"] as JsonObject;
            var errorCode = (Str(error?["code"]) ?? Str(obj?["code"]) ?? "").ToLowerInvariant();
            if (errorCode is "insufficient_quota" or "arrearage" or "allocationquota.freetieronly") throw new SuggestionException(Diagnostic.ProviderQuota);
            if (errorCode is "model_not_found" or "invalid_model" or "model_not_supported") throw new SuggestionException(Diagnostic.ModelUnavailable);
            var parameter = Str(error?["param"]) ?? "";
            if (code is 400 or 422 && (errorCode == "unsupported_parameter" || parameter is "temperature" or "response_format" or "max_tokens" or "max_completion_tokens" or "enable_thinking"))
                throw new SuggestionException(Diagnostic.UnsupportedParameter);
            throw new SuggestionException(Diagnostic.HttpStatus, code);
        }
        if (obj is null) throw new SuggestionException(Diagnostic.InvalidResponse);

        string content;
        if (native)
        {
            var stop = Str(obj["stop_reason"]);
            if (stop == "max_tokens") throw new SuggestionException(Diagnostic.Truncated);
            if (stop == "refusal") throw new SuggestionException(Diagnostic.Refused);
            if (stop != "end_turn" || obj["content"] is not JsonArray blocks) throw new SuggestionException(Diagnostic.InvalidResponse);
            content = string.Concat(blocks.OfType<JsonObject>().Where(b => Str(b["type"]) == "text").Select(b => Str(b["text"])));
        }
        else
        {
            if (obj["choices"] is not JsonArray { Count: > 0 } choices || choices[0] is not JsonObject choice
                || choice["message"] is not JsonObject message)
                throw new SuggestionException(Diagnostic.InvalidResponse);
            var finish = Str(choice["finish_reason"]);
            if (finish == "length") throw new SuggestionException(Diagnostic.Truncated);
            if (finish == "content_filter" || message["refusal"] is JsonValue) throw new SuggestionException(Diagnostic.Refused);
            if (finish != "stop" || Str(message["content"]) is not { } body) throw new SuggestionException(Diagnostic.InvalidResponse);
            content = body;
        }
        // Accept a single JSON code fence, never extract JSON from explanatory prose.
        var json = content.Trim();
        if (json.StartsWith("```json\n") && json.EndsWith("\n```")) json = json[8..^4];
        else if (json.StartsWith("```\n") && json.EndsWith("\n```")) json = json[4..^4];
        return json;
    }

    static string? Str(JsonNode? node) => node is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;
}
