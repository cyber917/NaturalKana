# 开发说明

[返回首页](../README.md)

## 仓库结构

| 路径 | 内容 |
| --- | --- |
| `NaturalSuggestCore/` | 本项目新增的 Swift 包：建议引擎（`NaturalSuggestCore`）、设置与候选 UI（`NaturalSuggestUI`）、主程序与键盘共享存储（`NaturalKanaStorage`）、命令行调试工具 |
| `NaturalSuggestCore/Sources/NaturalSuggestCore/Resources/Languages/` | 语言包：每种建议语言一个文件夹，iPhone、Mac、Windows 共用，见[添加一种语言](#添加一种语言) |
| `NaturalSuggestCore/Sources/NaturalSuggestCore/Resources/ui_strings.json` | 界面文字的英文、日文翻译（以中文原文为索引），三端共用 |
| `patches/ios.patch`、`patches/macos.patch` | 对上游 azooKey iOS／Desktop 的修改 |
| `Config/Brand.json` | 公开的默认应用标识；`rebrand.py` 据此生成工程中的标识 |
| `Config/Dependencies/*.resolved` | 固定的 Swift 依赖版本 |
| `tools/` | 准备源码、改标识、导出补丁、构建和安装 Mac 输入法的脚本 |
| `windows/` | Windows 建议小助手（C# / .NET 8），核心逻辑从 `NaturalSuggestCore` 移植，见 [WINDOWS.md](WINDOWS.md#从源码构建) |
| `upstream/` | `bootstrap.py` 下载的上游源码（不提交到仓库） |

上游固定版本写在 `tools/bootstrap.py` 里。`bootstrap.py` 下载上游和子模块，应用补丁，复制依赖锁文件；加 `--weights` 会下载模型。

## 添加一种语言

每种建议语言是 `Resources/Languages/<id>/` 下的一个文件夹，`<id>` 就是保存在设置里的名字（例如 `korean`）。三端都会自动读到它，不需要改 Swift 或 C# 代码：

| 文件 | 内容 |
| --- | --- |
| `language.json` | 名称、例句、分组名、识别规则（字段见下表） |
| `prompt.txt` | 给模型的说明（英文写），参考 `english/prompt.txt` 的结构；例句需要母语者审核 |
| `lexicon.jsonl` | 可选：网络用语参考词库，格式同 `japanese/lexicon.jsonl`，释义写在 `gloss_<语言>` 字段 |

`language.json` 的字段：

| 字段 | 说明 |
| --- | --- |
| `order` | 设置里的排列顺序 |
| `title` | 界面上的名称（中文，例如“韩语”）；英文、日文翻译加到 `ui_strings.json` |
| `promptName` | 提示词里的语言名，例如 `Korean` |
| `locale` | 语言代码，例如 `ko` |
| `testDraft` | “测试连接”时发送的例句，最好带一个常见错误 |
| `registerTitles` | 分组名，用这种语言写：`{"casual": "반말", "polite": "존댓말"}` |
| `closeTitle`、`copyHint` | Mac 建议框的“关闭”和复制提示，用这种语言写 |
| `rules` | 新语言写 `generic`；`japanese`、`english`、`chinese` 是三种已有语言专门调过的规则 |
| `generic` | `rules` 为 `generic` 时的检查规则：`letters`（这种语言的字母，正则字符类，如 `[\\uAC00-\\uD7A3]`）、`forbidden`（候选里不能出现的字母）、`latinAllowlist`（候选里允许的英文词）、`denied`（翻译、指令类请求的关键词，小写）、`draftShare`／`candidateShare`（这种语言字母至少占多少，默认 0.5／0.6） |
| `detect` | 建议语言选“自动”时用：`signal`（看到就判定为这种语言的字符，正则）、`priority`（数字小的优先）、`ambiguousWith`（没有 `signal` 时，主要语言是这些语言的用户不会被判定成这种语言） |
| `keepPunctuation` | 候选保留全角标点（中文用） |
| `romanizedInput` | 用罗马字或拼音输入，结尾是英文字母说明还在拼写（Windows 自动建议用） |
| `windowsFont` | Windows 建议卡片的字体 |

加完后运行 `swift test --package-path NaturalSuggestCore`：测试会检查每个语言包是否完整、例句能否通过检查、界面名称有没有翻译。Windows 的测试在 GitHub 上运行。iPhone 和 Mac 输入法要能直接打这种语言，还需要另外加键盘布局。

## 修改上游代码

直接在 `upstream/azooKey-ios` 或 `upstream/azooKey-macos` 里改，然后导出补丁：

```sh
python3 tools/export_patches.py
```

导出时会把本地标识（`Config/LocalBrand.json`，不提交）换回公开标识，并清空签名 Team。提交前运行：

```sh
swift test --package-path NaturalSuggestCore
python3 tools/check_public_source.py
```

`check_public_source.py` 会检查将要提交的文件里有没有本地标识、疑似密钥和个人路径。不要提交 API 密钥、证书、描述文件、个人词库或已签名的 App。

## 共享存储（iPhone）

主程序和键盘扩展通过 App Group 共享设置，通过共享钥匙串组共享 API 密钥。

- `NaturalKanaStorage/SharedContainer.swift`：AltStore／SideStore 重签时会在 `Info.plist` 写入 `ALTAppGroups`，有它就用其中唯一匹配本应用的组，没有就用 Xcode 构建时配置的组。共享容器不可用时显示 G01–G04 错误提示，不会悄悄退回到私有存储。
- `NaturalKanaStorage/SharedKeychain.swift`：用一个不含敏感信息的探针项读出系统实际分配的钥匙串访问组前缀，再用共享组存取密钥。不假设 Team ID 等于 App ID 前缀。
- App 的 设置 → 高级设置 → “检查共享权限”会用随机标记验证主程序和键盘能否互相读到配置和钥匙串。

所以同一份 IPA 既可以用 Xcode 签名，也可以用 SideStore／AltStore 重签，共享功能都能用。

## 发布 IPA

Release 里的 IPA 是“重签输入包”：在 Mac 上用 Release 配置构建，只带 ad-hoc 签名，App Group 为 `group.org.naturalkana`，钥匙串组前缀是占位符 `NKADHOC000`。它不能直接安装，要由 SideStore 或 AltStore 用用户自己的 Apple ID 重签，重签时会替换成用户自己的组和前缀。

发布前检查：

1. 主程序和 Keyboard 扩展的版本号一致，Keyboard、框架、字典和两个模型都在包里。
2. 包里没有个人证书、描述文件或 Team ID。
3. 附上 `LICENSE`、`THIRD_PARTY_NOTICES.md` 和 `licenses/`，并在发布说明里给出 IPA 的 SHA256。

## 发布 Windows 版

1. 把 `windows/NaturalKana.Windows/NaturalKana.Windows.csproj` 里的 `<Version>` 改成新版本号，合并到 `main`。
2. 在 GitHub 的 Actions 页选 **Windows release** → **Run workflow**。它会在 Windows 机器上跑测试、打包，并创建草稿 Release `windows-v版本号`，附带 exe、许可证压缩包和 `SHA256SUMS.txt`。
3. 在 Releases 页打开草稿，补上更新内容，确认后点 **Publish release**。

## 设计取舍

- 保留 azooKey 的假名汉字转换；建议功能是独立的请求和候选 UI。
- 建议默认关闭，需要用户同意发送当前句子并配置密钥。请求默认用 HTTPS（本机和局域网地址可用 HTTP）、结构化输出、20 秒超时；草稿和回复不写入日志。
- 缓存只在内存中；设置、密钥或词库变化时失效。草稿变化会取消旧请求。
- iPhone 只在输入框末尾做安全替换；Mac 确认不了替换范围时改为复制候选。
- Mac 版转换用字典转换，因为神经网络 Metal 后端在实际输入测试中出过错。
