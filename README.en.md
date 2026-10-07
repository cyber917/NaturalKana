# NaturalKana

Japanese input and phrasing suggestions for macOS and iPhone.

Supports Qwen, OpenAI, DeepSeek, Kimi, Gemini, Claude, and custom endpoints. Includes casual/polite alternatives, personal vocabulary references, mixed-word Japanese drafts, and local change highlighting.

Use API model IDs rather than display names. Each provider keeps its own configuration and Keychain credential. Custom endpoints can use OpenAI-compatible Chat Completions or Claude Messages; JSON and token parameters are configurable.

See [中文说明](README.md) for setup, building, privacy and development notes.

Detailed guides (Chinese): [installation on Mac and iPhone](docs/INSTALLATION.md), [API configuration, usage and troubleshooting](docs/USAGE.md), and [SNS vocabulary import](docs/SNS词库使用说明.md). The installation guide explains source preparation, signing both iOS targets, Developer Mode, keyboard access, and adding the macOS input source. Builds currently target Apple Silicon Macs; the iPhone host app requires iOS 17.6 or later.

A derivative of [azooKey](https://github.com/azooKey/azooKey) and [azooKey-Desktop](https://github.com/azooKey/azooKey-Desktop), retaining their Japanese input engine and keyboard components and adding NaturalSuggestCore for phrasing suggestions. This is not an official azooKey release. See [source provenance (Chinese)](docs/PROVENANCE.md), [third-party notices](THIRD_PARTY_NOTICES.md), and the included licenses.

A small checkmark means the model explicitly judged the draft natural; a spinner means checking, and an exclamation mark signals a request failure. Tap the indicator on iPhone or hover on Mac for details. This assessment uses the same model request. Escape dismisses the Mac palette without changing the draft or clipboard.
