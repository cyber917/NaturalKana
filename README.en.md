# NaturalKana

[中文](README.md) · [Latest release](https://github.com/cyber917/NaturalKana/releases/latest) · [User guide](docs/USAGE.md)

Write a sentence, get more natural alternatives, and choose one to replace your draft. Supports Japanese, Chinese, English, Korean, French and Russian. Bring your own provider API key.

## Download and install

| Platform | What you get | Installation |
| --- | --- | --- |
| **iPhone** | Multilingual keyboard, iOS 17.6+ | [Download the IPA](https://github.com/cyber917/NaturalKana/releases/latest), then re-sign with SideStore / AltStore → [Guide](docs/INSTALLATION.md#iphone不需要-mac) |
| **Windows** | Suggestion helper, Windows 10/11 x64 | [Download the exe](https://github.com/cyber917/NaturalKana/releases/tag/windows-v0.1.3), use with your existing input method → [Guide](docs/WINDOWS.md) |
| **Mac** | Input method and menu-bar helper, Apple silicon, macOS 13+ | [Download the source installer](https://github.com/cyber917/NaturalKana/releases/latest); full Xcode and your own development signing setup required → [Guide](docs/MAC_INSTALL.md) |

The Mac installer builds from source; it is not a DMG. Free-account iPhone installations require regular renewal; see [signing and renewal](docs/INSTALLATION.md#签名与续期). Detailed guides are currently in Chinese.

## Features

- **Phrasing suggestions:** casual and polite alternatives with changes highlighted; optional Kansai-ben suggestions for Japanese.
- **Multilingual iPhone input:** Chinese pinyin, Japanese, English, Korean, French and Russian; configurable language switching and remembered keyboard language.
- **Offline candidates and learning:** mixed full/initial Chinese pinyin and limited typo correction; French, Russian and Korean word completion and local word memory.
- **Desktop shortcuts:** configurable check and select-all-and-check shortcuts on Mac and Windows; verify the original text before replacement, click outside to dismiss.
- **Providers and interface:** Qwen, OpenAI, DeepSeek, Kimi, Gemini, Claude and compatible endpoints; interface in Chinese, English or Japanese.

## Guides

| Topic | Documentation |
| --- | --- |
| Provider setup, keyboard settings, everyday use and troubleshooting | [User guide](docs/USAGE.md) |
| Personal slang vocabulary on Mac | [SNS vocabulary](docs/USAGE.md#sns-词库mac) |
| Building, repository structure, language packs, patches and releases | [Development](docs/DEVELOPMENT.md) |

## Privacy and license

Input conversion runs locally. Online suggestions send only the current sentence (up to 200 characters), style preferences and matching vocabulary entries directly to your configured provider. There is no NaturalKana server. Keys are stored in the device Keychain or Windows Credential Manager.

NaturalKana derives from [azooKey](https://github.com/azooKey/azooKey) and [azooKey-Desktop](https://github.com/azooKey/azooKey-Desktop); it is not an official upstream release. Original additions use the [MIT license](LICENSE). Upstream code, dictionaries, models and data retain their own licenses; see [third-party sources and notices](THIRD_PARTY_NOTICES.md) and [licenses/](licenses/).
