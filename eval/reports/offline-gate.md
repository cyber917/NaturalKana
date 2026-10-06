# offline-gate

Cases: 170. Dataset and gold references are synthetic and await native review.
Prompt: system_v1.txt. Slang: light.

Local non-Japanese / translation / injection rejections: 29/29.
Errors: 0. Errors never count as negative-case passes.

No API calls were made. No provider quality, all-negative pass rate, token cost, or network latency was measured.
Already-natural Japanese and some gibberish intentionally reach the server-side check; local rejection is not the product pass rate.

| Provider | Fast / quality model | Live comparison |
|---|---|---|
| OpenAI | Configurable | Not measured in offline audit |
| Qwen | Configurable | Not measured in offline audit |

Default model selection is pending real measurements.
