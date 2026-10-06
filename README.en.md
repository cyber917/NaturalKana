# NaturalKana

Japanese input and phrasing suggestions for macOS and iPhone.

Supports Qwen, OpenAI, DeepSeek, Kimi, Gemini, Claude, and custom endpoints. Includes casual/polite alternatives, personal vocabulary references, mixed-word Japanese drafts, and local change highlighting.

Use API model IDs rather than display names. Each provider keeps its own configuration and Keychain credential. Custom endpoints can use OpenAI-compatible Chat Completions or Claude Messages; JSON and token parameters are configurable.

See [中文说明](README.md) for setup, building, privacy and development notes.

Based on azooKey. See [third-party notices](THIRD_PARTY_NOTICES.md) and the included licenses.

A small checkmark means the model explicitly judged the draft natural; a spinner means checking, and an exclamation mark signals a request failure. Tap the indicator on iPhone or hover on Mac for details. This assessment uses the same model request. Escape dismisses the Mac palette without changing the draft or clipboard.
