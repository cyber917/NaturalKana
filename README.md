# NaturalKana

[English](README.en.md) · [下载最新版](https://github.com/cyber917/NaturalKana/releases/latest) · [使用说明](docs/USAGE.md)

打完一句话，给你更自然的表达建议，点一下替换原句。支持日语、中文、英语、韩语、法语和俄语，自备服务商 API 密钥。

## 下载与安装

| 平台 | 提供什么 | 安装方式 |
| --- | --- | --- |
| **iPhone** | 多语言键盘，iOS 17.6+ | [下载 IPA](https://github.com/cyber917/NaturalKana/releases/latest)，用 SideStore／AltStore 安装 → [教程](docs/INSTALLATION.md#iphone不需要-mac) |
| **Windows** | 建议小助手，Windows 10/11 64 位 | [下载 exe](https://github.com/cyber917/NaturalKana/releases/tag/windows-v0.1.4)，配合现有输入法使用 → [教程](docs/WINDOWS.md) |
| **Mac** | 输入法与菜单栏小助手，Apple 芯片、macOS 13+ | [下载源码安装器](https://github.com/cyber917/NaturalKana/releases/latest)，需要完整 Xcode 和自己的开发签名配置 → [教程](docs/MAC_INSTALL.md) |

Mac 提供的是源码编译安装器，不是 DMG。iPhone 免费账户安装后需定期续签，详见[签名与续期](docs/INSTALLATION.md#签名与续期)。

## 可以做什么

- **表达建议**：按口语、敬语分组，标出修改；日语可额外给出关西弁说法。
- **iPhone 多语言输入**：中文拼音、日语、英文、韩语、法语和俄语；可自定义语言切换顺序，记住上次使用的语言。
- **离线候选与记忆**：中文支持全拼／简拼混输和有限拼写纠错；法语、俄语、韩语支持词语补全和常用词记忆。
- **桌面快捷键**：Mac、Windows 都可一键全选输入框并检查，快捷键可改；采用建议前核对原文，点击窗口外部收起。
- **服务与界面**：支持 Qwen／百炼、OpenAI、DeepSeek、Kimi、Gemini、Claude 和兼容接口；界面可选中文、English、日本語。

## 使用与开发

| 内容 | 文档 |
| --- | --- |
| 配置接口、键盘设置、日常使用、排错 | [配置与使用](docs/USAGE.md) |
| 导入个人网络用语词库（Mac） | [SNS 词库](docs/USAGE.md#sns-词库mac) |
| 编译、项目结构、语言包和补丁、发布流程 | [开发说明](docs/DEVELOPMENT.md) |

## 隐私与许可

输入转换在本地完成。联网建议只发送当前句子（最多 200 字）、表达偏好和命中的词库条目，直接发给你配置的服务商；本项目没有服务器。密钥保存在设备钥匙串或 Windows 凭据管理器中。

NaturalKana 基于 [azooKey](https://github.com/azooKey/azooKey) 与 [azooKey-Desktop](https://github.com/azooKey/azooKey-Desktop)，不是上游官方版本。新增代码使用 [MIT 许可](LICENSE)；上游代码、字典、模型和数据各自保留原许可，见[第三方来源与说明](THIRD_PARTY_NOTICES.md)及 [licenses/](licenses/)。
