# Third-party notices

NaturalKana is a derivative of azooKey and azooKey-Desktop, not an official upstream release. Its root MIT license covers original NaturalKana additions; it does not replace third-party licenses. Preserve original notices when distributing. See docs/PROVENANCE.md for source mapping and the scope of this audit. The audit is incomplete where explicitly stated.

- azooKey-ios: MIT; full text in licenses/azooKey-ios.txt.
- azooKey-Desktop: MIT; full text in licenses/azooKey-Desktop.txt.
- swift-tokenizers: inspected LICENSE; full notice in licenses/swift-tokenizers-LICENSE.txt.
- swift-crypto: inspected LICENSE.txt; full notice in licenses/swift-crypto-LICENSE.txt.txt.
- swift-crypto: inspected NOTICE.txt; full notice in licenses/swift-crypto-NOTICE.txt.txt.
- swift-numerics: inspected LICENSE.txt; full notice in licenses/swift-numerics-LICENSE.txt.txt.
- swift-algorithms: inspected LICENSE.txt; full notice in licenses/swift-algorithms-LICENSE.txt.txt.
- SwiftyMarisa: inspected LICENSE.md; full notice in licenses/SwiftyMarisa-LICENSE.md.txt.
- swift-asn1: inspected LICENSE.txt; full notice in licenses/swift-asn1-LICENSE.txt.txt.
- swift-asn1: inspected NOTICE.txt; full notice in licenses/swift-asn1-NOTICE.txt.txt.
- ZIPFoundation: inspected LICENSE; full notice in licenses/ZIPFoundation-LICENSE.txt.
- swift-collections: inspected LICENSE.txt; full notice in licenses/swift-collections-LICENSE.txt.txt.
- Jinja: inspected LICENSE; full notice in licenses/Jinja-LICENSE.txt.
- AzooKeyKanaKanjiConverter: inspected LICENSE; full notice in licenses/AzooKeyKanaKanjiConverter-LICENSE.txt.

- azooKey_dictionary_storage: Apache-2.0 at pinned revision 4d418525b090cf49c219819d05a7e3cc2a4346eb; verbatim root LICENSE in licenses/azooKey-dictionary-LICENSE.txt. No root NOTICE was found. Underlying dictionary-source attribution still needs review before distributing built apps.
- SwiftyMarisa offers BSD-2-Clause or LGPL-2.1-or-later; NaturalKana uses the BSD-2-Clause option. The original combined license text is retained without alteration.
- ZIPFoundation: the bundled license is copied verbatim from the pinned 0.9.20 checkout (copyright 2017–2025).

Submodules:
- azooKey_emoji_dictionary_storage: no root LICENSE. Its data/README.md identifies BSD-3-Clause, Unicode data terms and MIT sources. Source attribution copied below; a distributable notice bundle still needs Unicode/BSD texts verified at the pinned data versions.
- zenz-v3.2-small-gguf and zenz-v3.2-xsmall-gguf: model-card metadata says Apache-2.0; no standalone LICENSE in either checkout. Upstream base-model and conversion provenance still need review. Local device builds downloaded LFS weights; weights are not included in this public source repository. A model-card license label alone does not complete a redistribution audit.
- base_n5_lm: no LICENSE or model card found in the pinned repository. License is unresolved; do not assume MIT for these weights.

Transitive binary targets (including the llama.cpp XCFramework), dictionary sources, emoji data terms and embedded model components still need a full release audit before distributing compiled apps. Root MIT licenses do not cover every data/model artifact. No statement of license-complete distribution is made.
