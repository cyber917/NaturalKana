# 安装教程

[返回首页](../README.md) · [配置与使用](USAGE.md)

- [iPhone（不需要 Mac）](#iphone不需要-mac)：Windows、Mac、Linux 电脑都可以
- [从源码构建 iPhone 版](#从源码构建-iphone-版)：需要 Mac 和 Xcode
- [Mac 输入法](#mac-输入法)：需要 Mac 和 Xcode

为什么需要签名、为什么每 7 天要续一次，见[首页说明](../README.md#为什么要签名为什么-7-天要续一次)。

## iPhone（不需要 Mac）

用 [iloader](https://github.com/nab138/iloader) 把 [SideStore](https://github.com/SideStore/SideStore) 装到手机上，再由 SideStore 安装 NaturalKana。SideStore 会用你自己的 Apple ID 在手机上完成签名，以后续签也在手机上完成，不需要电脑。

> 这条路线已在 Windows 11 + iPhone（iOS 26.7）+ 免费 Apple ID 上实测通过，包括键盘与主程序共享设置和 API 密钥。

### 准备

| 需要 | 说明 |
| --- | --- |
| iPhone | iOS 17.6 或更高，数据线 |
| Apple ID | 免费的就行，建议用手机上登录的那个 |
| 电脑 | Windows 10/11、macOS 或 Linux。Windows 要先装 [Apple 官网版 iTunes](https://www.apple.com/itunes/)，用来识别 iPhone |
| [iloader](https://github.com/nab138/iloader/releases) | Windows 下载 `iloader-windows-x64.msi` |
| NaturalKana 安装包 | 从 [Releases](https://github.com/cyber917/NaturalKana/releases) 下载 `.ipa` 文件 |

### 1. 用 iloader 安装 SideStore

1. 用数据线连接 iPhone，解锁，手机提示“要信任此电脑吗”时点**信任**。
2. 打开 iloader，用 Apple ID 登录。手机弹出验证码时，在 2 分钟内填进 iloader。
3. 右侧确认识别到了你的 iPhone，然后点 **SideStore (Stable)**。不要选 LiveContainer 版本，键盘扩展在里面用不了。
4. 等三步都打勾：下载 SideStore → 签名并安装 → 放置配对文件。

**如果弹出 “Maximum certificates reached”（证书已达上限）：** 免费账户能同时持有的证书很少，要先撤销一张。点 **Choose what to revoke** 看清单，**只撤销你不再需要的那张**。撤销某张证书后，用它签名的 App 会立刻打不开。比如你在 Mac 上用 Xcode 装过 App，带电脑名的那张就是 Xcode 在用的。

### 2. 在手机上设置 SideStore

1. **开发者模式**：设置 → 隐私与安全性 → 开发者模式 → 打开，按提示重启，重启后再确认一次。
2. **信任开发者**：如果打开 SideStore 时提示“未受信任的开发者”，到 设置 → 通用 → VPN 与设备管理，信任你的 Apple ID。
3. **LocalDevVPN**：在 App Store 安装 [LocalDevVPN](https://apps.apple.com/app/localdevvpn/id6755608044)（免费），打开后点 Connect 并允许添加 VPN 配置。它只在手机内部建一个本地通道，让 SideStore 能自己安装和续签 App，不是翻墙工具。**每次用 SideStore 安装或刷新前都要先连上它**；如果同时开着别的 VPN，先关掉别的。
4. 打开 SideStore，用同一个 Apple ID 登录。在 **My Apps** 里点 SideStore 旁边的 **7 DAYS** 刷新一次，完成初始化。

### 3. 把 IPA 传到手机

SideStore 从手机的“文件”App 里选择安装包，任选一种方式传过去：

- **Windows（推荐）**：iTunes → 点左上角的手机图标 → **文件共享** → 选 **SideStore** → **添加文件…** → 选择 IPA。这一步走数据线，不用联网。注意只用“文件共享”，**不要点同步或恢复**。
- **Mac**：访达 → 左侧选你的 iPhone → **文件** 标签 → 把 IPA 拖到 SideStore 上，或者直接用隔空投送。
- 也可以通过 iCloud 云盘或其他网盘传，传完在“文件”App 里能看到即可。

### 4. 用 SideStore 安装 NaturalKana

1. 确认 LocalDevVPN 已连接。
2. SideStore → **My Apps** → 左上角 **＋** → 选择 NaturalKana 的 IPA（用 iTunes 传的在“我的 iPhone → SideStore”里）。
3. 如果询问是否保留 App 扩展（App Extensions），选**保留**，键盘就是这个扩展。
4. 安装完成后，桌面出现 NaturalKana。

### 5. 添加键盘

1. 设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → 选 **NaturalKana**。
2. 点刚添加的 NaturalKana，打开**允许完全访问**（联网获取建议需要）。
3. 打开 NaturalKana App → 设置 → 表达建议，按[首次配置](USAGE.md#第一次配置)填写 API。
4. 可以在 App 的 设置 → 高级设置 里点**检查共享权限**，确认主程序和键盘能互相读到配置。

### 6. 每 7 天续签一次

打开 LocalDevVPN 连上 → SideStore → My Apps → **Refresh All**。这会把 SideStore 和 NaturalKana 一起续期。建议每 3～5 天做一次，不要拖到最后一天。

- SideStore 支持后台刷新，也可以用“快捷指令”设置自动刷新，但前提是刷新那一刻 LocalDevVPN 是连着的。这个功能是否稳定取决于系统和网络，建议仍定期手动打开看一眼剩余天数。
- 已经过期也不用重装 NaturalKana：只要 SideStore 还能打开，点刷新即可。如果 SideStore 自己也过期了，用电脑上的 iloader 重装 SideStore，然后在 SideStore 里刷新。

### 更新 NaturalKana

下载新版 IPA，按第 3、4 步再导入一次。SideStore 会覆盖安装同一个 App，设置和密钥保留。

### 常见问题

| 现象 | 处理 |
| --- | --- |
| iloader 登录报 `WebSocket protocol error` 或 `error sending request ... ani.sidestore.io` | 连接 anisette 服务器时网络中断（常见于代理不稳定）。直接重试；还不行就在 iloader 的 Settings 里换一个 Anisette Server，或换个代理节点 |
| iloader 一直停在 “Download SideStore” | 从 GitHub 下载太慢或连接卡住。关掉 iloader 重开，再试；必要时换个代理节点 |
| “Maximum certificates reached” | 见第 1 步。不要无脑全选撤销 |
| SideStore 安装或刷新失败，提示连接设备相关错误 | 确认 LocalDevVPN 已连接、没有同时开其他 VPN；仍失败时用 iloader 的 **Manage Pairing File** 重新放置配对文件 |
| 提示 App 数量达到上限 | 免费账户同一台手机最多 3 个自签 App（含 SideStore）。删掉一个不用的自签 App 后重试 |
| 升级 iOS 后 SideStore 不能用了 | 配对文件可能失效，用 iloader 重新放置配对文件，或重装 SideStore |
| App 打不开，提示无法验证 | 签名过期或证书被撤销。在 SideStore 刷新；如果证书被撤销了，重新导入 IPA |
| 键盘能打字但没有建议 | 检查“允许完全访问”和 API 配置，见[排查顺序](USAGE.md#没有建议时按这个顺序排查) |

**关于 AltStore／AltServer：** 本项目同样兼容 AltStore（会读取 AltStore 写入的 App Group 信息）。但在 2026 年 10 月的实测中，Windows 版 AltServer 1.8 在安装 AltStore 时反复报 `Your session has expired (1100)`，同一账户换用 iloader 则正常，所以 Windows 用户推荐走上面的路线。

## 从源码构建 iPhone 版

需要 Mac、从 App Store 安装的完整 Xcode、Python 3、Git、[Git LFS](https://git-lfs.com/)。

### 1. 下载源码

```sh
git clone https://github.com/cyber917/NaturalKana.git
cd NaturalKana
python3 tools/bootstrap.py --weights
```

看到 `Pinned sources ready` 即完成。网页上的 “Download ZIP” 不包含上游源码和模型，必须运行 `bootstrap.py`。

### 2. 改成自己的应用标识（推荐）

默认标识是 `org.naturalkana`。自己签名时，Apple 可能不允许注册别人已用过的标识，建议改成自己的：编辑 `Config/Brand.json`，把除 `name` 外的四项改成你的名字，例如：

```json
{
  "name": "NaturalKana",
  "bundlePrefix": "com.yourname.naturalkana",
  "iosAppGroup": "group.com.yourname.naturalkana",
  "macAppGroup": "group.com.yourname.naturalkana.mac",
  "macBundleIdentifier": "com.yourname.inputmethod.naturalkana"
}
```

> **Mac 输入法的标识必须包含 `.inputmethod.` 这一段**（前后都有点），例如 `com.yourname.inputmethod.naturalkana`。`com.yourname.naturalkana.inputmethod` 这种 `inputmethod` 在末尾的写法不行：安装和注册都会显示成功，但 macOS 会拒绝加载，系统设置里永远找不到它。`rebrand.py` 遇到这种标识会直接报错。

然后运行：

```sh
python3 tools/rebrand.py
```

它会一并修改主程序、键盘、App Group 和钥匙串组。不要只在 Xcode 里改某一个 Bundle Identifier，否则主程序和键盘无法共享设置。以后更新时保持同一套标识，否则旧设置和密钥无法沿用。

### 3. 签名并运行

1. `open NaturalKana.xcworkspace`，在 Xcode → Settings → Accounts 登录 Apple ID。
2. 点左侧最上方的 `azooKey` 工程，分别给 **`azooKey`** 和 **`Keyboard`** 两个 target 在 Signing & Capabilities 里选**同一个 Team**。
3. 运行方案选 **MainApp**，设备选你的 iPhone。Product → Scheme → Edit Scheme → Run 把 Build Configuration 改成 **Release**。
4. iPhone 打开开发者模式，保持解锁，按 `⌘R`。
5. 按上面的[第 5 步](#5-添加键盘)添加键盘。

工程里保留了上游的名字（`azooKey`、`MainApp` 等），用户看到的名字是 NaturalKana。免费账户签名的版本 7 天后要重新运行一次。

## Mac 输入法

> **第一次装、不熟悉终端？请看[Mac 详细安装教程](MAC_INSTALL.md)**：装好 Xcode 后，用一条命令就能完成下载、编译和安装，教程里也有更新、卸载和常见问题。下面是给熟悉开发的人的简略版。

需要 Apple 芯片的 Mac 和 macOS 13 以上。准备源码和应用标识同上面的第 1、2 步。Mac 的 `macAppGroup` 建议写成 `你的TeamID.` 加上 `macBundleIdentifier`，例如 `AB12CD34EF.com.yourname.inputmethod.naturalkana.mac`。然后：

1. 在 Xcode → Settings → Accounts 登录 Apple ID，并在 Manage Certificates 里确认有 Apple Development 证书。用 `security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject` 查 Team ID（`OU=` 后面的 10 位）。
2. 先检查模型，再构建：

   ```sh
   python3 tools/verify_mac_models.py
   export NATURALKANA_TEAM_ID='你的 Team ID'
   bash tools/build_macos.sh --signed
   ```

3. 切换到系统自带的输入法，然后安装：

   ```sh
   mkdir -p .build-local/bin
   xcrun swiftc tools/register_input_source.swift -o .build-local/bin/register-input-source
   python3 tools/install_macos.py \
     --app .build-local/macos/native/Build/Products/Release/azooKeyMac.app \
     --registrar .build-local/bin/register-input-source
   ```

4. 系统设置 → 键盘 → 文字输入 → 编辑… → `+` → 日语 → 添加 NaturalKana。列表里没有的话，退出登录再登录一次。还是没有，就打开一次上面的输入法列表，然后在终端运行：

   ```sh
   log show --last 5m --predicate 'process == "imklaunchagent"' | grep 'Refusing connection'
   ```

   有输出说明系统拒绝了这个 Bundle ID：检查 `Config/Brand.json` 里的 `macBundleIdentifier` 是否包含 `.inputmethod.`，改好后重新运行 `rebrand.py`、构建和安装。
5. 菜单栏选 **NaturalKana（日本語）**，在输入法菜单里打开“NaturalKana 设置…”，填写 API。

输入法菜单中的 **NaturalKana（English）** 是英文模式，在设置里把建议语言改成英语后也会给出英文建议；Apple 自带的“日语”输入法不会显示本项目的建议。找不到设置入口时运行 `zsh tools/open_macos_settings.command`。

## 反馈问题

提交 Issue 时写清安装方式、设备和系统版本、进行到哪一步、完整报错文字。截图前遮住邮箱、设备标识和 API 密钥，不要上传证书或描述文件。
