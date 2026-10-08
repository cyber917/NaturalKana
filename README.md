# NaturalKana

[English](README.en.md)

带 AI 表达建议的日语输入工具：iPhone 键盘、macOS 输入法，以及 Windows 建议小助手。打完一句日语，就能得到更自然的口语／敬语说法，点一下即可替换。

基于 [azooKey](https://github.com/azooKey/azooKey) 与 [azooKey-Desktop](https://github.com/azooKey/azooKey-Desktop) 的衍生项目，日语输入引擎和键盘沿用上游，新增了表达建议功能。不是 azooKey 官方版本。

- 支持 Qwen／百炼、OpenAI、DeepSeek、Kimi、Gemini、Claude 和自定义兼容接口（自备 API 密钥）
- 口语和敬语分组，最多 10 条建议，标出改动的部分
- 句子里夹着不会说的英文、中文词，也能给出日语说法
- 可导入自己的网络用语词库（Mac）

## 安装

| 你有的设备 | 推荐方式 |
| --- | --- |
| **Windows / Mac / Linux 电脑 + iPhone** | 下载现成的 IPA，用 SideStore 安装，不需要 Mac 和 Xcode → [教程](docs/INSTALLATION.md#iphone不需要-mac) |
| Mac + iPhone，想自己改代码 | 用 Xcode 从源码构建 → [教程](docs/INSTALLATION.md#从源码构建-iphone-版) |
| Mac（输入法，Apple 芯片） | 用 Xcode 从源码构建 → [详细教程](docs/MAC_INSTALL.md) |
| **Windows 电脑** | 下载 exe，配合任何日语输入法使用：按 Ctrl+Alt+J，或打开自动建议 → [说明](docs/WINDOWS.md) |

iPhone 版需要 iOS 17.6 或更高；Windows 版需要 Windows 10/11（64 位）。安装包都在 [Releases](https://github.com/cyber917/NaturalKana/releases) 页面。

装好后到 App 里填写服务商、模型 ID 和 API 密钥，再在系统键盘设置里打开“允许完全访问”。详见[配置与使用](docs/USAGE.md)。

## 为什么要“签名”，为什么 7 天要续一次

**iPhone 不允许运行没有 Apple 签名的 App**，自己编译的也不例外。不经过 App Store 安装时，App 要用某个 Apple 账户签名，签名的有效期取决于账户类型：

| 签名方式 | 有效期 | 费用 | 到期前要做什么 |
| --- | --- | --- | --- |
| 免费 Apple ID + SideStore（本项目推荐） | 7 天 | 免费 | 在手机上打开 SideStore 点刷新，不需要电脑 |
| 免费 Apple ID + Xcode | 7 天 | 免费 | 用 Mac 重新运行一次 |
| 付费开发者账户（99 美元／年） | 1 年 | 付费 | 一年重装一次 |

- 过期后 App 和键盘会打不开，但**设置和密钥一般不会丢**，刷新或重新安装同一个 App 后就能继续用。
- 免费账户的限制：同一台手机最多同时装 3 个自签 App（SideStore 自己占 1 个）；每 7 天最多注册 10 个 App ID（NaturalKana 主程序和键盘共用 2 个）。
- SideStore 本身也是 7 天签名。只要在到期前点过刷新，它就会连同自己一起续期。如果已经过期，要回到电脑上用 iloader 重装 SideStore，NaturalKana 不用重装。
- **Mac 版**：macOS 对本地构建的程序宽松得多，通常不需要每周续期；如果哪天输入法加载不了，重新执行一遍构建和安装即可。
- **Windows 版**：没有有效期，下载就能一直用。第一次运行时 Windows 可能提示“已保护你的电脑”，点“更多信息 → 仍要运行”即可（程序没有购买代码签名证书）。

## 隐私

联网建议只发送当前这一句（最多 200 字）、表达偏好和命中的词库条目，直接发到你自己配置的服务商；本项目没有服务器。API 密钥保存在设备钥匙串（Windows 上是凭据管理器）里。键盘的“完全访问”只用于联网获取建议。

## 从源码构建

需要 Mac、完整 Xcode、Python 3、Git 和 Git LFS。

```sh
git clone https://github.com/cyber917/NaturalKana.git
cd NaturalKana
python3 tools/bootstrap.py --weights
open NaturalKana.xcworkspace
```

`bootstrap.py` 会下载固定版本的上游源码和模型，再应用 `patches/` 里的修改。签名和安装步骤见[安装教程](docs/INSTALLATION.md#从源码构建-iphone-版)，仓库结构和开发说明见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。

## 许可

NaturalKana 新增的代码使用 MIT 许可（[LICENSE](LICENSE)）。上游 azooKey、转换引擎、字典、模型和其他依赖各自保留原许可，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)、[licenses/](licenses/) 和[来源核对](docs/PROVENANCE.md)。
