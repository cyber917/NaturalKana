# 安装教程

[返回首页](../README.md) · [配置与使用](USAGE.md)

目前发布的是源码，需要在 Mac 上用 Xcode 构建。Mac 输入法和 iPhone 键盘分别安装；打开开发预览窗口不等于安装系统输入法。

第一次安装按下面的顺序操作：

1. [准备工具并下载源码](#准备工具并下载源码)。
2. [设置自己的应用标识](#设置自己的应用标识)。
3. 选择 [Mac 安装](#mac-安装)或 [iPhone 安装](#iphone-安装)。
4. [填写 API 配置并测试](USAGE.md#第一次配置)。

## 准备工具并下载源码

### 1. 准备工具

| 工具或设备 | 用途与要求 |
| --- | --- |
| Mac | 构建两端应用。Mac 输入法的构建脚本目前面向 Apple Silicon（M 系列）；Intel Mac 未验证 |
| 完整 Xcode | 从 App Store 安装，首次打开后完成许可确认和组件下载；只有 Command Line Tools 不够 |
| Python 3 | 运行源码准备、标识生成和安装脚本 |
| Git、Git LFS | 下载源码、依赖和输入引擎的模型文件 |
| Apple Account | 在 Xcode 中配置自己的开发签名 |
| iPhone 与数据线 | 仅安装 iPhone 版时需要；当前主应用要求 iOS 17.6 或更高 |

Mac 输入法工程的最低系统版本为 macOS 13；安装 Xcode 还需要满足所用 Xcode 版本的系统要求。建议使用能在当前系统运行的较新稳定版 Xcode。

打开「终端」，逐行检查工具：

```sh
python3 --version
git --version
git lfs version
```

能显示版本号就可以。缺少 Python 时，安装 [Python 3](https://www.python.org/downloads/macos/)。如果已经装了 Homebrew，可用下面的命令安装 Git LFS：

```sh
brew install git-lfs
git lfs install
```

没有 Homebrew 时，可按 [Git LFS 官网](https://git-lfs.com/)的说明安装，不必为了本项目专门安装 Homebrew。

在以下命令中指定 Xcode 路径。这只影响当前终端窗口：

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

应显示完整 Xcode 的版本。如果 Xcode 安装在别处，将路径换成实际位置。后面的命令都在同一个终端窗口运行；新开窗口需要重新设置 `DEVELOPER_DIR`。

### 2. 下载与准备源码

下面的命令把项目放在「文稿」里的 `NaturalKana` 文件夹。已有同名文件夹时，换一个目录名，避免覆盖自己的文件。

```sh
cd ~/Documents
git clone https://github.com/cyber917/NaturalKana.git
cd NaturalKana
python3 tools/bootstrap.py --weights
```

最后一条命令会下载固定版本的上游源码、子模块及模型文件，并应用本项目的修改。第一次需要联网，下载完成前不要打开 Xcode 开始构建。

看到 `Pinned sources ready` 表示准备完成。Mac 版再检查一次模型文件：

```sh
python3 tools/verify_mac_models.py
```

检查应通过。模型下载不完整时先解决问题，不要安装缺少模型的输入法。

推荐用 `git clone` 下载；网页上的「Download ZIP」只包含本仓库文件，不能代替依赖和模型下载。即使下载了 ZIP，也仍需运行 `bootstrap.py --weights`。

## 设置自己的应用标识

应用标识用于签名，以及区分应用的设置和钥匙串。公开源码中的 `org.naturalkana` 是默认值；自行构建时建议改成自己的标识，避免与别人注册的标识冲突。

完成源码准备后，用文本编辑器打开项目里的 [`Config/Brand.json`](../Config/Brand.json)。保留 `name`，修改另外四项。例如：

```json
{
  "name": "NaturalKana",
  "bundlePrefix": "com.example.yourname.naturalkana",
  "iosAppGroup": "group.com.example.yourname.naturalkana",
  "macAppGroup": "group.com.example.yourname.naturalkana.mac",
  "macBundleIdentifier": "com.example.yourname.inputmethod.naturalkana"
}
```

**将示例中的 `example.yourname` 换成自己的唯一名称，不要原样照抄。** 标识使用英文字母、数字、点和连字符，不要填邮箱、中文或空格。保存后，在项目目录执行：

```sh
python3 tools/rebrand.py
open NaturalKana.xcworkspace
```

生成脚本会一起修改应用、键盘扩展、App Group 和钥匙串组。不要只在 Xcode 中改某一个 Bundle Identifier，否则主应用与键盘可能无法共享配置。

**后续更新保持这些标识和签名 Team 一致。** 改标识会让系统把它当成另一套应用，原设置和密钥可能无法继续使用。

## Mac 安装

### 1. 配置开发签名

1. 在 Xcode 菜单打开「Xcode → Settings… → Accounts」，登录自己的 Apple Account。
2. 选择账户和 Team。如果还没有开发证书，在「Manage Certificates…」中创建 `Apple Development` 证书。
3. 打开 `NaturalKana.xcworkspace`，按 `Command + 1` 显示左侧项目导航。
4. 点击最上层蓝色工程图标 `azooKeyMac`，在工程编辑器的 **TARGETS** 中选 `azooKeyMac`。
5. 打开「Signing & Capabilities」，勾选「Automatically manage signing」，Team 选择自己的开发团队。
6. 在同一 target 的「Build Settings」搜索 `Development Team`，复制实际 Team ID。它通常是 10 位字母数字，和账户昵称不同。

若 Xcode 提示某项 capability 不受当前团队支持，先按报错核对账户权限。不要直接删除 App Group 或钥匙串共享项来绕过错误；它们关系到配置和密钥能否共享。账户能力可参考 [Apple 开发账户说明](https://developer.apple.com/help/account/basics/about-your-developer-account)。

### 2. 构建可安装的版本

回到终端的项目目录，把下面的占位文字换成自己的 Team ID：

```sh
export NATURALKANA_TEAM_ID='YOUR_TEAM_ID'
bash tools/build_macos.sh --signed
```

脚本会先构建转换服务，再构建并签名输入法。成功后显示的应用路径为：

```text
.build-local/macos/native/Build/Products/Release/azooKeyMac.app
```

`--compile-only` 只检查编译，产物未签名，不能当作这一步的安装包。第一次编译可能要较长时间；以终端是否报错和是否显示构建成功为准。

### 3. 安装并注册输入源

先切换到系统的 `ABC` 或其他输入法。然后在项目目录依次执行：

```sh
mkdir -p .build-local/bin
xcrun swiftc tools/register_input_source.swift -o .build-local/bin/register-input-source
python3 tools/install_macos.py \
  --app .build-local/macos/native/Build/Products/Release/azooKeyMac.app \
  --registrar .build-local/bin/register-input-source
```

安装器会检查签名和模型，把应用放到 `~/Library/Input Methods/NaturalKana.app`，并注册输入法及转换服务。它不会替你切换当前输入法。

如果末尾出现 `Manual setup required`，表示还需要下一步手动添加输入源，不能据此判断安装失败。

### 4. 在系统设置中添加

1. 打开「系统设置 → 键盘 → 文字输入 → 编辑…」。英文系统对应「Keyboard → Text Input → Edit…」。
2. 点击 `+`，在日语分类中找到 NaturalKana 并添加。
3. 关闭设置，点击菜单栏的输入法图标，选择 **NaturalKana（日本語）**。

如果列表里没有 NaturalKana，先关闭再打开系统设置。仍没有时，保存其他应用的工作后退出登录并重新登录，再检查；必要时重启 Mac。不要反复复制不同版本到多个 Input Methods 目录。

菜单中的几项含义如下：

| 输入源 | 什么时候用 |
| --- | --- |
| NaturalKana（日本語） | 常规日语输入，罗马字转假名、汉字，并提供表达建议 |
| NaturalKana（English） | 输入英文字母；需要在日语里夹一个英文词时可临时切换 |
| Japanese／日语 | Apple 自带输入法，不会显示本项目的建议 |

### 5. 打开设置并验收

选择 NaturalKana 后，点击输入法菜单中的「NaturalKana 设置…」，打开「日语建议」。找不到入口时，可在项目目录运行：

```sh
zsh tools/open_macos_settings.command
```

按[首次配置步骤](USAGE.md#第一次配置)保存 API 设置，再在备忘录的新笔记里测试。能输入日语、能显示建议或自然状态标志，才算完成安装与联网配置。

## iPhone 安装

### 1. 连接并开启开发者模式

1. 用能传输数据的线连接 iPhone 与 Mac，保持手机解锁。
2. 手机弹出「信任此电脑」时确认，并在手机上输入自己的锁屏密码。
3. 在 Xcode 的设备界面确认能看到手机。不同版本可能叫「Device Hub」，或位于「Window → Devices and Simulators」。
4. 在 iPhone 打开「设置 → 隐私与安全性 → 开发者模式」，开启开关。
5. 按提示重启手机；重启后解锁，在再次出现的确认框中点「开启」，完成密码确认。

仅打开开关、没有完成重启后的确认还不够。「锁定模式／Lockdown Mode」是另一个功能，不是开发者模式。如果暂时看不到开发者模式，先完成 Xcode 与手机配对。参见 [Apple 开发者模式说明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。

### 2. 找到正确的工程、target 和运行方案

打开根目录的 `NaturalKana.xcworkspace`。Xcode 保留了一些上游工程名，它们不是多个不同的应用：

| 名称 | 在哪里 | 要做什么 |
| --- | --- | --- |
| `azooKey` | 左侧蓝色工程图标 | 点击它打开 iPhone 工程配置 |
| `azooKey` target | 工程编辑器中的 TARGETS | 配置主应用的签名 |
| `Keyboard` target | 同一个 TARGETS 列表 | 配置键盘扩展的签名 |
| `MainApp` scheme | 顶部运行按钮旁的运行方案菜单 | 安装主应用和随附键盘时选择它 |
| `MainApp` 文件夹 | 左侧源码目录 | 只是放代码的文件夹，不是运行方案菜单 |
| `azooKeyTests` 等 | 测试方案或测试 target | 普通安装不选这些 |

**看不到 TARGETS 时：** 按 `Command + 1`，点击左侧最上层蓝色图标和 `azooKey` 名称这一行，不是只点旁边展开箭头，也不是点击 `MainApp` 文件夹。右侧出现工程配置后，左边应有 PROJECT / TARGETS；窗口太窄时把它放大。

### 3. 给主应用和键盘扩展分别签名

1. 在「Xcode → Settings… → Accounts」登录自己的 Apple Account。
2. 选择 `azooKey` target →「Signing & Capabilities」。
3. 勾选「Automatically manage signing」，Team 选自己的团队。
4. 切换到 `Keyboard` target，重复第 2、3 步，选择**同一个 Team**。
5. 确认两者的 Bundle Identifier、App Group 和钥匙串组已由前面的标识生成步骤统一设置。键盘的 Bundle Identifier 应是主应用标识加 `.keyboard`。

如果报 `Signing for "Keyboard" requires a development team`，说明键盘 target 还没选 Team；只给主应用选 Team 不够。

免费 Apple Account 可以在 Xcode 中使用 Personal Team 做个人设备测试，但存在账户和 capability 限制；能否签下本工程以 Xcode 的实际检查为准。Personal Team 的 provisioning profile 有效期为 **7 天**，到期通常需要重新构建安装。发布到 App Store 和更多开发能力需要相应开发者计划。参见 [Apple 开发账户说明](https://developer.apple.com/help/account/basics/about-your-developer-account)。

### 4. 选择手机并运行

1. 点击 Xcode 顶部运行方案菜单，选 **MainApp**。
2. 点它旁边的运行设备菜单，选自己的实体 iPhone 名称。不要选模拟器或 `Any iOS Device`。
3. 为了正常使用时的性能，在「Product → Scheme → Edit Scheme… → Run → Info」将「Build Configuration」设为 **Release**。
4. 保持 iPhone 解锁，点击左上角 `▶`，或按 `Command + R`。
5. 等待构建、安装完成。手机应出现并打开 NaturalKana 应用。

如果手机提示「不受信任的开发者」，按提示到「设置 → 通用 → VPN 与设备管理」，核对是自己用于签名的开发者后信任，再打开应用。

### 5. 添加键盘并允许联网

1. iPhone 打开「设置 → 通用 → 键盘 → 键盘 → 添加新键盘…」。
2. 选择 NaturalKana。
3. 返回键盘列表，点 NaturalKana，开启 **允许完全访问**。
4. 打开 NaturalKana 应用 →「设置 → 日语建议」，完成[首次配置](USAGE.md#第一次配置)。

完全访问用于让键盘联网获取建议。应用还会单独询问是否允许发送当前句子；两处都启用才会调用模型。发送范围见[隐私说明](USAGE.md#数据与隐私)。

Mac 与 iPhone 的服务商配置和密钥**不会自动同步**。请在手机上单独填写并保存，不能只配置电脑。

### 6. 做一次完整测试

1. 先在 NaturalKana 应用里点「测试连接」，确认能返回建议或显示无需修改状态。
2. 在 iPhone 备忘录里新建笔记，长按地球键，切换到 NaturalKana。
3. 输入一句日语，完成假名／汉字转换，光标留在句尾，停顿一下。
4. 查看建议卡片或小状态图标。出现建议后可左右翻页，点句子采用，点 `×` 关闭。

主应用能联网、键盘没反应时，优先检查「允许完全访问」、当前是否真的使用 NaturalKana，以及两套 target 的共享配置是否一致。密码框等受保护输入框中，iOS 可能自动改回系统键盘。

## 更新已安装的版本

先保存原项目的 `Config/Brand.json` 和签名 Team 信息。不要把自己的密钥、签名文件或个人词库提交到公开仓库。

如果自己没有修改源码，可以在**新的文件夹**下载最新版，运行 `bootstrap.py --weights`，再把原来的 `Config/Brand.json` 复制到新项目中，运行 `rebrand.py`。这样保留应用身份，同时避免旧依赖或本地改动影响更新。

- Mac：用原 Team 重新执行签名构建和安装步骤；安装前切换到其他输入法，安装后重新选择 NaturalKana。必要时退出登录以结束旧版本进程。
- iPhone：用原 Team、原应用标识，选择 MainApp 和原手机运行。通常直接覆盖安装，不必先删除旧应用。

使用免费 Personal Team 的 iPhone 安装到期，也按相同身份重新运行。不要为了解决到期提示随意换 Bundle Identifier。

## 安装常见问题

| 现象 | 先做什么 |
| --- | --- |
| `python3` 或 `git lfs` 找不到 | 回到工具准备步骤；`git lfs` 是单独的工具，不是安装 Git 就一定有 |
| `xcodebuild` 只找到 Command Line Tools | 设置本教程的 `DEVELOPER_DIR`，确认指向完整 Xcode |
| GitHub、依赖或 LFS 下载失败 | 先确认终端能访问相应网站，处理网络后重跑准备命令；不要跳过模型文件检查 |
| `unexpected revision; existing checkout preserved` | 本地上游不是脚本要求的版本。保留自己的修改，在新文件夹准备干净源码 |
| 找不到 `NaturalSuggestCore` 或 package product | 确认准备命令已成功、从根目录打开 workspace；等待 Xcode 解析依赖完成 |
| `requires a development team` | 在报错所指的 target 选择自己的 Team，主应用和 Keyboard 都要配置 |
| Bundle Identifier 不可用或无法注册 | 按「设置自己的应用标识」生成自己的标识，再重新检查签名 |
| capability 不受当前 Team 支持 | 核对 Apple 账户权限和 capability；不要单独删除共享组来绕过签名 |
| Xcode 仍说开发者模式没开 | 确认重启后的第二次开启已完成；手机解锁后拔插数据线，重新检查设备状态 |
| `developer disk image could not be mounted` | 打开错误详情。先核对 Xcode 是否支持手机当前 iOS，完成设备支持组件下载、配对和开发者模式；若详情是下载／授权连接失败，再检查 Mac 和手机网络、代理或 VPN。不能仅凭这句断定是 VPN |
| Xcode 说设备锁定 | 解锁手机并保持屏幕亮着，再运行 |
| Mac 菜单里没有 NaturalKana | 确认已执行安装器，在键盘设置手动添加；仍没有时退出登录再登录 |
| Mac 能打罗马字但不转日语 | 选 NaturalKana（日本語）；English 是英文输入模式 |
| 能打字，但没有建议 | 看[建议不出现的排查顺序](USAGE.md#没有建议时按这个顺序排查)，输入法安装与 API 配置是两步 |

仍不能解决时，提交 Issue 时写出安装平台、系统版本、Xcode 版本、进行到哪一步，以及完整报错文字。截图先遮住邮箱、设备标识、密钥和聊天内容；不要上传证书或 provisioning profile。
