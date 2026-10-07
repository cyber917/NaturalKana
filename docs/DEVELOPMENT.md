# 开发说明

[返回首页](../README.md)

## 仓库结构

| 路径 | 内容 |
| --- | --- |
| `NaturalSuggestCore/` | 本项目新增的 Swift 包：建议引擎（`NaturalSuggestCore`）、设置与候选 UI（`NaturalSuggestUI`）、主程序与键盘共享存储（`NaturalKanaStorage`）、命令行调试工具 |
| `patches/ios.patch`、`patches/macos.patch` | 对上游 azooKey iOS／Desktop 的修改 |
| `Config/Brand.json` | 公开的默认应用标识；`rebrand.py` 据此生成工程中的标识 |
| `Config/Dependencies/*.resolved` | 固定的 Swift 依赖版本 |
| `tools/` | 准备源码、改标识、导出补丁、构建和安装 Mac 输入法的脚本 |
| `upstream/` | `bootstrap.py` 下载的上游源码（不提交到仓库） |

上游固定版本写在 `tools/bootstrap.py` 里。`bootstrap.py` 下载上游和子模块，应用补丁，复制依赖锁文件；加 `--weights` 会下载模型。

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

## 设计取舍

- 保留 azooKey 的假名汉字转换；建议功能是独立的请求和候选 UI。
- 建议默认关闭，需要用户同意发送当前句子并配置密钥。请求用 HTTPS、结构化输出、20 秒超时；草稿和回复不写入日志。
- 缓存只在内存中；设置、密钥或词库变化时失效。草稿变化会取消旧请求。
- iPhone 只在输入框末尾做安全替换；Mac 确认不了替换范围时改为复制候选。
- Mac 版转换用字典转换，因为神经网络 Metal 后端在实际输入测试中出过错。
