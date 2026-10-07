# 代码来源与许可核对

核对日期：2026-10-07。范围：公开源码、固定的上游版本、补丁与保存的许可文件。此次核对不是完整安装包的法律审查，也不表示所有模型和数据的再分发授权已经确认。

## 项目与上游的关系

NaturalKana 是基于 azooKey 与 azooKey-Desktop 的衍生项目，不是从零实现的输入法，也不是 azooKey 官方版本。日语转换、键盘和输入法基础大量沿用上游；新增的主要部分是日语表达建议及其接入、配置和交互。

[azooKey 官方开源说明](https://azookey.com/OpenSource) 明确允许任何人基于 azooKey 制作自己的键盘应用。两份主项目采用 MIT；修改、发布和再分发须保留原版权及许可声明。[MIT 原文](https://opensource.org/license/mit)没有规定最低修改比例，也没有要求产品名、模块名与上游完全一致。名称不同不转移原作者的版权。

`LICENSE` 只覆盖 NaturalKana 的原创新增部分。第三方代码、字典、模型与二进制组件各自保留原许可，不能统一认定为 MIT。

## 来源与修改对应

| 本项目位置或名称 | 来源 | 复用与改动 |
| --- | --- | --- |
| `upstream/azooKey-ios`、`patches/ios.patch` | [azooKey/azooKey](https://github.com/azooKey/azooKey) | 复用 iOS 键盘、布局、按键、学习、用户词典和主题组件；改写设置入口，接入表达建议、候选卡片及状态指示，调整菜单和显示名称。 |
| `upstream/azooKey-macos`、`patches/macos.patch` | [azooKey/azooKey-Desktop](https://github.com/azooKey/azooKey-Desktop) | 复用 InputMethodKit 输入法基础、日语输入与转换交互；接入候选窗、关闭快捷键、状态指示和统一设置，移除旧建议路径及对应设置。 |
| `AzooKeyCore`、`Core`、`KanaKanjiConverterModule` 等 | 上游及 [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter) | 日语输入与假名汉字转换来自上游，不是 NaturalKana 自研转换引擎。 |
| `NaturalSuggestCore/Sources` | NaturalKana 新增代码 | 请求调度、取消与缓存，多服务商协议，候选校验，混合语言草稿识别，个人与 SNS 词库参考，本地改动高亮和结果状态。 |
| `NaturalSuggestCore/Sources/NaturalSuggestUI/` 中的 `NaturalSettingsView.swift`、`SuggestionModel.swift`、`IOSSuggestionPanel.swift`、`MacSession.swift` 等 | NaturalKana 新增代码，结合上游 UI 和输入生命周期 | 建议引擎在两平台上的设置、展示和采用行为。新增文件通过上游补丁接入。 |
| `azooKey.xcodeproj`、`azooKeyMac.xcodeproj`、`azooKey` target、`MainApp` scheme 等 | 上游工程名称 | 部分工程名保留，以减少构建变更；用户看到的产品名为 NaturalKana。两者不同不表示来源被替换。 |

上游已经有 OpenAI 的「いい感じ変換 / Magic Conversion」功能。NaturalKana 不是第一个给 azooKey 加入 AI 的项目；本项目重做了表达建议路径，并加入上述多服务商、词库、校验和交互功能。

## 固定版本与改动量

`tools/bootstrap.py` 使用以下主项目版本：

- iOS：`b50db4aec1069a8d2341f70415da3bdc61f1fce6`。
- macOS：`bd90b7bdc8f38069987b36426b990ef3129edf62`。

对照本次核对前的公开提交 `721a61e`：

| 范围 | 变更量 |
| --- | --- |
| iOS 上游补丁 | 27 个文件，新增 431 行、删除 464 行。 |
| macOS 上游补丁 | 39 个文件，新增 332 行、删除 4052 行。 |
| 独立建议核心 | 17 个 Swift 源文件，1745 行；另有 9 个测试文件，779 行。 |

这些是补丁统计和物理行数，不是原创比例。macOS 删除量主要包括旧建议功能及设置的移除，不能当作新增原创代码。未修改的上游文件以及下载的依赖也不会体现在补丁变更量中。

## 已核实的许可与署名

- `licenses/azooKey-ios.txt`、`licenses/azooKey-Desktop.txt` 与上述固定版本的原始根目录 `LICENSE` 逐字节一致，包含原作者版权声明。
- `licenses/AzooKeyKanaKanjiConverter-LICENSE.txt` 与两平台所用转换器版本的根目录 MIT 许可一致。
- 已核对保存的 Jinja、swift-algorithms、swift-collections、swift-numerics、swift-tokenizers、swift-asn1、swift-crypto、SwiftyMarisa 许可；swift-asn1 与 swift-crypto 的 `NOTICE` 也保留。
- ZIPFoundation 许可已改为所用 0.9.20 版本的原文，纠正此前从其他版本复制的版权年份差异。
- 新增 `licenses/azooKey-dictionary-LICENSE.txt`，保留默认字典仓库固定版本 `4d418525b090cf49c219819d05a7e3cc2a4346eb` 的 Apache-2.0 原文；未发现根目录 `NOTICE`。
- 重写但保留的 `SettingsHomeView.swift` 已恢复原作者文件头，并标记 NaturalKana 的修改。删除旧文件不需要为署名重新引入废弃功能；全局上游许可仍须保留。

许可证全文与进一步说明见 [第三方说明](../THIRD_PARTY_NOTICES.md) 和 [licenses](../licenses/)。本节只确认所列的文件，不代表所有间接依赖都已核对。

## 尚未确认的部分

| 组件 | 当前证据 | 尚缺的确认 |
| --- | --- | --- |
| `base_n5_lm`，固定版本 `160a305a89c033ac53a674baeac4470cf531a71b` | 未找到 LICENSE、README 或模型卡。 | 模型及相关词表的再分发授权。不能因主项目为 MIT 就假定权重也为 MIT。 |
| `zenz-v3.2-small-gguf`、`zenz-v3.2-xsmall-gguf` | 模型卡标为 Apache-2.0，没有独立许可文件。 | 基础模型、转换过程与附带文件的来源及再分发声明。 |
| 默认字典 | 固定版本根许可为 Apache-2.0。 | 其底层词典数据来源及可能要求保留的附加声明。 |
| `azooKey_emoji_dictionary_storage` | 数据说明列出 Mozc BSD-3-Clause、Unicode 数据条款及 MIT 来源。 | 对应固定数据版本的完整许可文本与署名清单。 |
| `llama.cpp` XCFramework 等间接二进制组件 | 转换器依赖配置中包含二进制下载。 | 二进制内各组件的许可及附带声明。 |

[Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0)对保留许可、相关声明、修改说明及适用的 NOTICE 有要求，也不授予上游商标使用权。仅保留主项目的一份 MIT 文件，不能解决所有组件的授权问题。

## 公开源码与安装包的区别

本次检查的公开源码树不包含模型权重、编译后的应用或上游图片资源。仓库主要发布新增代码、补丁、构建脚本和许可；`upstream/` 由脚本从原来源下载，不提交到本仓库。检查过的历史 `NaturalKana-source.zip` 也未包含模型权重或图片。

这不能等同于完整安装包已经通过审查。本机构建时下载过模型权重，某些被关闭的功能仍可能在打包时带入模型。公开分发 `.app`、`.pkg` 或 `.ipa` 前，应检查实际包内容并解决上表中涉及的授权与声明；不能用「功能没开启」代替检查。

API 密钥、签名身份、个人词库和设备信息不属于公开源码。隐私检查与许可检查是两项不同的工作，均不能互相替代。
