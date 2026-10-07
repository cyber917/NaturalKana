# NaturalKana

[中文](README.md)

A Japanese keyboard for iPhone and input method for macOS with AI phrasing suggestions. Type a Japanese sentence, pause, and NaturalKana offers more natural casual or polite alternatives above the keyboard. Tap one to replace your draft.

NaturalKana is derived from [azooKey](https://github.com/azooKey/azooKey) and [azooKey-Desktop](https://github.com/azooKey/azooKey-Desktop). It keeps their Japanese input engine and keyboard and adds the suggestion feature. It is not an official azooKey release.

- Bring your own API key: Qwen, OpenAI, DeepSeek, Kimi, Gemini, Claude, or any OpenAI-compatible / Claude Messages endpoint
- Casual and polite groups, up to 10 candidates, with changes highlighted
- Handles Japanese drafts that mix in English or Chinese words
- Optional personal slang vocabulary (Mac)

## Install

- **iPhone, no Mac needed (Windows / macOS / Linux):** download the IPA from [Releases](https://github.com/cyber917/NaturalKana/releases), install [SideStore](https://github.com/SideStore/SideStore) with [iloader](https://github.com/nab138/iloader), then import the IPA in SideStore. Requires iOS 17.6+.
- **Build from source (Mac + Xcode):** iPhone app and macOS input method.

Step-by-step guides are in Chinese: [docs/INSTALLATION.md](docs/INSTALLATION.md). Configuration and troubleshooting: [docs/USAGE.md](docs/USAGE.md).

## Signing and the 7-day limit

iOS only runs apps signed through Apple. Apps signed with a free Apple ID expire after **7 days**. With SideStore you renew them on the phone (LocalDevVPN connected → SideStore → Refresh All), with no computer needed. A paid Apple Developer account extends this to one year. Free accounts are limited to 3 sideloaded apps per device, including SideStore, and 10 App IDs per 7 days. NaturalKana uses 2 App IDs: the app and its keyboard. macOS is far more permissive with locally built apps; the input method normally does not need weekly renewal (rebuild and reinstall if it ever stops loading).

## Privacy

Only the current sentence (up to 200 characters), your style preferences and matching vocabulary entries are sent, directly to the provider you configure. There is no NaturalKana server. API keys are stored in the device Keychain.

## Build

```sh
git clone https://github.com/cyber917/NaturalKana.git
cd NaturalKana
python3 tools/bootstrap.py --weights
open NaturalKana.xcworkspace
```

Requires full Xcode, Python 3, Git and Git LFS. See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## License

Original NaturalKana code is MIT ([LICENSE](LICENSE)). Upstream code, dictionaries, models and dependencies keep their own licenses. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [licenses/](licenses/).
