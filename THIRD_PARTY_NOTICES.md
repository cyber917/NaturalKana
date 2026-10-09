# Third-party notices

NaturalKana is a derivative of azooKey and azooKey-Desktop, not an official upstream release. Its root MIT license covers original NaturalKana additions; it does not replace third-party licenses. Preserve original notices when distributing. Source mapping and audit scope are included below. The audit is incomplete where explicitly stated.

## Sources and scope

The source and license review was recorded on 2026-10-07, with iPhone build 17 package notes added on 2026-10-08. Consolidating these notes does not constitute a new complete redistribution audit.

| Project files | Upstream source and role |
| --- | --- |
| `patches/ios.patch`, generated `upstream/azooKey-ios` | [azooKey](https://github.com/azooKey/azooKey), pinned at `b50db4aec1069a8d2341f70415da3bdc61f1fce6`; Japanese conversion, keyboard layouts, learning, themes and settings foundation. |
| `patches/macos.patch`, generated `upstream/azooKey-macos` | [azooKey-Desktop](https://github.com/azooKey/azooKey-Desktop), pinned at `bd90b7bdc8f38069987b36426b990ef3129edf62`; InputMethodKit integration and conversion UI. |
| Converter packages | [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter); upstream Japanese conversion engine. |
| `NaturalSuggestCore`, `NaturalSuggestUI`, desktop helpers | NaturalKana additions: provider requests, settings, candidate validation, vocabulary, UI and host-app integration. |

Upstream project and target names remain in Xcode to limit build changes; the visible product name is NaturalKana. Upstream azooKey already provides its own phrasing/conversion feature. These additions do not imply ownership of the upstream input engine or priority over upstream features. Retained upstream files keep their original copyright headers.

The public source tree does not include fetched model weights or compiled applications. A clean source audit does not establish that all data and models inside a compiled app are cleared for redistribution. Review the actual package and component-specific terms, including notices and unresolved items below. Private credentials, signing profiles and personal vocabulary must not be included in public artifacts.

## Code licenses

- azooKey-ios: MIT; full text in licenses/azooKey-ios.txt.
- azooKey-Desktop: MIT; full text in licenses/azooKey-Desktop.txt.
- swift-tokenizers: inspected LICENSE; full notice in licenses/swift-tokenizers-LICENSE.txt.
- swift-crypto: inspected LICENSE.txt; full notice in licenses/swift-crypto-LICENSE.txt.
- swift-crypto: inspected NOTICE.txt; full notice in licenses/swift-crypto-NOTICE.txt.
- swift-numerics: inspected LICENSE.txt; full notice in licenses/swift-numerics-LICENSE.txt.
- swift-algorithms: inspected LICENSE.txt; full notice in licenses/swift-algorithms-LICENSE.txt.
- SwiftyMarisa: inspected LICENSE.md; full notice in licenses/SwiftyMarisa-LICENSE.md.txt.
- swift-asn1: inspected LICENSE.txt; full notice in licenses/swift-asn1-LICENSE.txt.
- swift-asn1: inspected NOTICE.txt; full notice in licenses/swift-asn1-NOTICE.txt.
- ZIPFoundation: inspected LICENSE; full notice in licenses/ZIPFoundation-LICENSE.txt.
- swift-collections: inspected LICENSE.txt; full notice in licenses/swift-collections-LICENSE.txt.
- Jinja: inspected LICENSE; full notice in licenses/Jinja-LICENSE.txt.
- AzooKeyKanaKanjiConverter: inspected LICENSE; full notice in licenses/AzooKeyKanaKanjiConverter-LICENSE.txt.

- azooKey_dictionary_storage: Apache-2.0 at pinned revision 4d418525b090cf49c219819d05a7e3cc2a4346eb; verbatim root LICENSE in licenses/azooKey-dictionary-LICENSE.txt. No root NOTICE was found. Underlying dictionary-source attribution still needs review before distributing built apps.
- SwiftyMarisa offers BSD-2-Clause or LGPL-2.1-or-later; NaturalKana uses the BSD-2-Clause option. The original combined license text is retained without alteration.
- ZIPFoundation: the bundled license is copied verbatim from the pinned 0.9.20 checkout (copyright 2017–2025).

## Models and data
- azooKey_emoji_dictionary_storage: no root LICENSE. Its data/README.md identifies BSD-3-Clause, Unicode data terms and MIT sources. Source attribution copied below; a distributable notice bundle still needs Unicode/BSD texts verified at the pinned data versions.
- zenz-v3.2-small-gguf and zenz-v3.2-xsmall-gguf: model-card metadata says Apache-2.0; no standalone LICENSE in either checkout. Upstream base-model and conversion provenance still need review. Local device builds downloaded LFS weights; weights are not included in this public source repository. A model-card license label alone does not complete a redistribution audit.
- base_n5_lm (pinned revision `160a305a89c033ac53a674baeac4470cf531a71b`): no LICENSE or model card found in the pinned repository. License is unresolved; do not assume MIT for these weights.

### iPhone package review (build 17)
- Emoji data from Mozc (`emoji_data.tsv`): BSD-3-Clause, Copyright 2010-2018 Google Inc.; full text in licenses/mozc-LICENSE.txt.
- Emoji sequences and CLDR annotations from Unicode: Unicode License v3; full text in licenses/Unicode-LICENSE.txt. Source list in licenses/emoji-data-attribution.md.
- llama.cpp / ggml (inference runtime used by the converter): MIT; full text in licenses/llama.cpp-LICENSE.txt.
- zenz-v3.2-small and zenz-v3.2-xsmall GGUF models (Miwa-Keita): Apache-2.0 per model card.
- base_n5_lm is not included in the iPhone IPA; it is used only by the macOS build.

## Windows package
- Self-contained .NET 8 runtime, WPF and Windows Forms (Microsoft, MIT); full texts in licenses/dotnet-runtime-LICENSE.txt and licenses/dotnet-wpf-LICENSE.txt. Their own third-party notices: https://github.com/dotnet/runtime/blob/main/THIRD-PARTY-NOTICES.TXT
- Uses the same prompt files and lexicon as NaturalSuggestCore; contains no dictionaries or models.

Transitive binary targets (including the llama.cpp XCFramework), dictionary sources, emoji data terms and embedded model components still need a full release audit before distributing compiled apps. Root MIT licenses do not cover every data/model artifact. No statement of license-complete distribution is made.

## Offline keyboard completion data
- French, Russian and Korean word lists are adapted from wordfreq 3.1.1 (Robyn Speer), CC BY-SA 4.0. Script filtering and a Korean polite-form supplement are described in `NaturalSuggestCore/Sources/NaturalSuggestCore/Resources/KeyboardLexicons/ATTRIBUTION.md`, which retains the upstream source notices. These data files retain CC BY-SA 4.0; the root MIT license does not replace their license. The exporter uses the Apache-2.0 licensed wordfreq package.
- The Chinese pinyin dictionary (`KeyboardLexicons/zh-pinyin.txt`) is adapted from the same wordfreq 3.1.1 data, CC BY-SA 4.0, with readings generated by pypinyin 0.55.0 (mozillazg, MIT; license in `KeyboardLexicons/pypinyin-LICENSE.txt`). Details are in the same `ATTRIBUTION.md`.
