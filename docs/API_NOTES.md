# API documentation checked 2026-10-07

Chat Completions endpoints use bearer credentials and `POST <baseURL>/chat/completions`. Claude uses `POST <baseURL>/messages`, `x-api-key`, and `anthropic-version: 2023-06-01`. All providers disable streaming and use a 20-second timeout. OpenAI sends `max_completion_tokens` and `store=false`; other compatible presets send `max_tokens`. Output is bounded by max(2,048, selected candidate count × 768). Temperature is omitted by default, including when migrating older settings that injected it automatically. Quality mode compares the selected provider with a configurable partner, followed by a judge.

Automatic JSON format uses schema for OpenAI/Qwen/Gemini and JSON object for DeepSeek/Kimi. Custom and native Claude default to prompt-constrained JSON. Users can explicitly override format and token parameters; there is no silent retry or format downgrade. Strict local candidate validation applies to every protocol. A single JSON code fence is accepted; explanatory prose is not. Full completion/message endpoint URLs are accepted without appending a second suffix. Model IDs containing internal whitespace are rejected before sending credentials.

The input gate permits unknown foreign words inside Japanese sentence structure; standalone foreign sentences and instruction/translation requests remain rejected. Only an unfinished roman suffix blocks composition; embedded foreign words do not. Output uses the separate strict Japanese validator. Candidate differences are computed with a bounded local grapheme comparison and require no extra provider request.

References actually read:

- [OpenAI structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs): JSON Schema with strict mode; refusals/truncation still require handling. The client rejects refusals, non-stop finish reasons and malformed payloads.
- [GPT-4.1 mini](https://developers.openai.com/api/docs/models/gpt-4.1-mini) and [GPT-4.1](https://developers.openai.com/api/docs/models/gpt-4.1): documented comparison candidates, not measured defaults. Runtime settings leave IDs empty. Some newer models do not accept temperature; `ProviderConfiguration.temperature=nil` omits it.
- [OpenAI web search](https://developers.openai.com/api/docs/guides/tools-web-search): refresh uses the Responses API and hosted `web_search`, not scraping.
- [Qwen OpenAI compatibility](https://www.alibabacloud.com/help/en/model-studio/compatibility-of-openai-with-dashscope): account region/workspace determines credentials and endpoint. Retrieved international and mainland pages contain inconsistent region examples. Use the exact endpoint shown by the user's console; do not guess a workspace ID.
- [Qwen structured output](https://help.aliyun.com/en/model-studio/qwen-structured-output): strict schema is limited to selected models/series; Users can select JSON object for a model that does not support schema. The retrieved page lists Qwen3.8 Flash/Max and Qwen3.7 families for JSON Schema; examples use `qwen3.8-max`. Check account access before choosing a live model.
- [Qwen web search](https://www.alibabacloud.com/help/en/model-studio/web-search): official search can be enabled with `enable_search`; native DashScope search results expose sources with `enable_source`. The refresh tool uses the native text-generation API for Qwen and requires an `/api/v1` base URL, while the app requires the OpenAI-compatible `/compatible-mode/v1` URL.

Traditional compatible examples are `https://dashscope-intl.aliyuncs.com/compatible-mode/v1` (international) and `https://dashscope.aliyuncs.com/compatible-mode/v1` (mainland). Current docs also show workspace-specific Singapore (`https://{WorkspaceId}.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1`) and Beijing (`https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1`) endpoints. The app's international URL is an editable starting value, not an assertion of account compatibility. Unexpanded placeholders are rejected.

Qwen has been exercised in native development tests. Automated HTTP/error handling is verified with mocked transport; this does not establish production reliability or model quality. Unsupported schema/model/temperature errors remain silent in the typing UI and are surfaced as status; the client never silently changes models, retries parameters, or downgrades the selected response format.

Stability update: identical in-flight requests and repeated notifications for a completed draft are coalesced. Changed drafts/settings still cancel stale requests. Explicitly natural results are cached; unknown empty replies are not. No automatic paid retries or model switching are performed. Status distinguishes timeout, network failure, HTTP status, known provider-quota errors, truncation, refusal, malformed JSON and a valid response with no acceptable suggestions. Raw provider error messages, drafts and keys are never logged or displayed as diagnostics.

Responses now contain an `assessment` (`natural`, `rewrite`, or `unsupported`) alongside `suggestions`. Only `natural` with an empty candidate list produces the small checkmark. Legacy empty responses remain unknown; contradictions and rejected candidates never produce a checkmark. The assessment uses the existing request, without a second model call. macOS displays a compact status panel near the caret; iOS places the indicator in the existing conversion bar without adding keyboard height. iOS coalesces draft capture after host changes so cancellation is followed by a request for the settled text.

Native macOS installation uses a separate sandboxed application; verify its opt-in and provider settings in the input-method menu before testing AI suggestions. A successful converter-service probe does not test Qwen or host text replacement.


Additional protocol references:

- [Gemini OpenAI compatibility](https://ai.google.dev/gemini-api/docs/openai)
- [Claude Messages](https://platform.claude.com/docs/en/api/messages/create)
- [DeepSeek JSON output](https://api-docs.deepseek.com/guides/json_mode/)
- [Kimi provider configuration](https://github.com/MoonshotAI/kimi-code/blob/main/docs/zh/configuration/providers.md)

The mixed draft `いえいえー clickしたらpasteをできる` returned five locally validated candidates in a native Mac Qwen check. New provider request/authentication formats are covered by mock transport tests; this is not a claim that every model/account has been live-tested.

Model IDs are API identifiers, not display labels. For example, [GPT-5.6 Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol) uses `gpt-5.6-sol` and supports Chat Completions and structured output. Account access still needs a live check.
