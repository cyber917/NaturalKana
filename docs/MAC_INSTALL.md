# Mac 输入法安装教程（详细版）

[返回首页](../README.md) · [安装教程总览](INSTALLATION.md) · [配置与使用](USAGE.md)

Mac 版目前**没有现成的安装包**，需要在你自己的 Mac 上从源码编译。听起来复杂，但每一步都是复制一条命令、粘贴、回车。第一次装大约需要 1 小时，大部分时间在等下载和编译。

> 为什么没有 DMG？给别人用的 Mac 程序必须用付费开发者账号（每年 99 美元）签名并交给苹果公证，否则会被系统拦截。自己编译则用免费 Apple ID 就行。

## 开始前确认

| 要求 | 怎么确认 |
| --- | --- |
| **Apple 芯片的 Mac**（M1、M2、M3、M4……） | 左上角  → 关于本机，“芯片”一栏写着 Apple M 开头。**Intel 芯片的 Mac 暂不支持** |
| macOS 13 或更新 | 同一个窗口里的 macOS 版本号 |
| 可用磁盘空间 50 GB 以上 | Xcode 本身就很大 |
| 一个 Apple ID | 免费的就可以，不需要付费开发者账号 |
| 一个大模型服务商的 API 密钥 | 装好后才用到，见[配置与使用](USAGE.md#第一次配置) |

## 第 0 步：学会用“终端”

教程里的命令都在“终端”里运行：

1. 按 `⌘ 空格` 打开聚焦搜索，输入 `终端`（或 `Terminal`），回车打开。
2. 复制教程里灰色框中的**一条**命令，在终端里按 `⌘ V` 粘贴，再按回车。
3. 等它跑完：最后一行重新出现 `%` 或 `$` 提示符，才能输入下一条。
4. 输入密码时屏幕上**不会显示任何字符**，这是正常的，输完直接回车。

> 遇到报错不要慌，先看文末的[常见问题](#常见问题)。问别人时，把终端里**最后 20 行左右**的文字一起发过去。

## 第 1 步：安装 Xcode

1. 打开 App Store，搜索 **Xcode**，点“获取”安装。文件很大，可能要下载很久。
2. 装好后**打开一次 Xcode**：同意许可协议，等它装完附加组件（如果问要装哪些平台，至少保留 macOS）。看到欢迎窗口后可以关掉。
3. 回到终端，运行下面这条，确认 Xcode 可用（会要求输入开机密码）：

   ```sh
   sudo /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -license accept
   ```

   没有输出、直接回到提示符就是成功。

## 第 2 步：安装 Homebrew 和 Git LFS

模型文件比较大，需要 Git LFS 才能下载；Git LFS 用 Homebrew 安装。

1. 已经装过 Homebrew 的跳过这一步。否则运行（来自 [brew.sh](https://brew.sh/zh-cn/) 官网）：

   ```sh
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

   按提示输入密码、按回车。**装完后终端会提示“Next steps”，把它让你运行的两三条命令也照着运行一遍**，否则下一步会提示找不到 `brew`。

2. 安装 Git LFS：

   ```sh
   brew install git-lfs
   ```

   ```sh
   git lfs install
   ```

   看到 `Git LFS initialized.` 就好了。

## 第 3 步：在 Xcode 里登录 Apple ID 并创建证书

1. 打开 Xcode，菜单栏 **Xcode → Settings…**（旧版叫 Preferences）→ **Accounts**。
2. 点左下角 `+` → **Apple ID**，登录你的 Apple ID。
3. 登录后在右边选中你的账号（Team 一栏通常是“你的名字 (Personal Team)”），点 **Manage Certificates…**。
4. 如果列表里没有 **Apple Development**，点左下角 `+` → **Apple Development** 创建一个，然后点 Done。

## 第 4 步：查出你的 Team ID

Team ID 是一串 10 位的字母和数字，后面好几步都要用。在终端运行：

```sh
security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
```

输出里 `OU=`（有的电脑显示成 `OU = `）后面的 10 位就是 Team ID。例如看到 `OU=AB12CD34EF`，Team ID 就是 `AB12CD34EF`。**把它记下来。**

> 提示 `The specified item could not be found` 说明还没有证书，回到第 3 步第 4 点创建。如果你的 Apple ID 属于多个团队，输出的可能不是你想用的那个，以 Xcode 里选的团队为准。

## 第 5 步：下载源码

下面的命令会把项目下载到你的个人文件夹里的 `NaturalKana` 文件夹：

```sh
cd ~ && git clone https://github.com/cyber917/NaturalKana.git
```

```sh
cd ~/NaturalKana && python3 tools/bootstrap.py --weights
```

第二条要下载上游源码和模型，可能需要十几分钟。看到 `Pinned sources ready` 就完成了。

> 不要用网页上的“Download ZIP”，那样下载不到上游源码和模型。

## 第 6 步：设置你自己的应用标识

每个人要用自己的一套标识，否则签名时会和别人冲突。

1. 用文本编辑打开配置文件：

   ```sh
   cd ~/NaturalKana && open -e Config/Brand.json
   ```

2. 把内容**整个替换**成下面这样，然后保存（`⌘ S`）、关闭：

   ```json
   {
     "name": "NaturalKana",
     "bundlePrefix": "com.yourname.naturalkana",
     "iosAppGroup": "group.com.yourname.naturalkana",
     "macAppGroup": "TEAMID.com.yourname.inputmethod.naturalkana.mac",
     "macBundleIdentifier": "com.yourname.inputmethod.naturalkana.mac"
   }
   ```

   需要你改的地方：
   - 所有的 `yourname` 换成你自己的英文名或拼音，只用小写字母和数字，例如 `xiaoming`。
   - `TEAMID` 换成第 4 步查到的 Team ID，例如 `AB12CD34EF.com.xiaoming.inputmethod.naturalkana.mac`。
   - **`macBundleIdentifier` 里必须保留 `.inputmethod.` 这一段**，否则装好后系统设置里会找不到输入法。

   > 如果文本编辑把英文引号自动换成了弯引号（`“ ”`），配置会读取失败。可以先在文本编辑的菜单 **编辑 → 替换 → 智能引号** 里关掉，再粘贴。

3. 让配置生效：

   ```sh
   cd ~/NaturalKana && python3 tools/rebrand.py
   ```

   最后一行出现 `Generated identities and patches updated` 就成功了。

## 第 7 步：编译

把下面第一条里的 `你的TeamID` 换成第 4 步的 Team ID，再运行：

```sh
export NATURALKANA_TEAM_ID='你的TeamID'
```

```sh
cd ~/NaturalKana && bash tools/build_macos.sh --signed
```

第一次编译要下载依赖，通常 10～30 分钟，期间终端会滚动大量文字，这是正常的。如果弹出窗口问能否使用钥匙串里的证书，输入开机密码并选“始终允许”。

最后出现 `** BUILD SUCCEEDED **` 和 `Build output: …azooKeyMac.app` 就成功了。

> 关掉终端后 `export` 设置会失效。之后重新编译时，要先再运行一次 `export` 那一行。

## 第 8 步：安装

1. 先把当前输入法切换成**系统自带的**（例如“ABC”或“简体拼音”）。如果你在更新旧版，这一步尤其重要。
2. 依次运行：

   ```sh
   cd ~/NaturalKana && mkdir -p .build-local/bin && xcrun swiftc tools/register_input_source.swift -o .build-local/bin/register-input-source
   ```

   ```sh
   cd ~/NaturalKana && python3 tools/install_macos.py --app .build-local/macos/native/Build/Products/Release/azooKeyMac.app --registrar .build-local/bin/register-input-source
   ```

   出现 `Installed: …/Library/Input Methods/NaturalKana.app` 就装好了。

## 第 9 步：添加输入法

1. 打开 **系统设置 → 键盘**，找到“文字输入”下的 **输入法 → 编辑…**。
2. 点左下角 `+`，在左侧语言里选 **日语**，在右边找到 **NaturalKana**，点“添加”。
3. 在菜单栏的输入法图标里选择 **NaturalKana（日本語）**。

列表里找不到 NaturalKana 的话，先**退出登录再登录一次**（左上角  → 退出登录），通常就会出现。还是没有，看[常见问题](#常见问题)。

## 第 10 步：填写 API，开始使用

1. 切换到 NaturalKana，点菜单栏的输入法图标 → **NaturalKana 设置…** → **表达建议**。
2. 打开“允许发送当前句子”和“表达建议”，选择服务商，填写接口地址、模型 ID 和 API 密钥，点**保存设置**，再点**测试连接**。

详细说明见[配置与使用](USAGE.md#第一次配置)。打一句日语、完成假名／汉字转换后停顿一下，光标旁边就会出现建议。

## 更新到新版本

你的标识写在 `Config/Brand.json` 里，更新前先备份，更新后再放回去：

```sh
cd ~/NaturalKana && cp Config/Brand.json ~/NaturalKana-Brand.json
```

```sh
cd ~/NaturalKana && for d in upstream/azooKey-macos upstream/azooKey-ios; do git -C "$d" checkout -- . && git -C "$d" clean -fd; done
```

```sh
cd ~/NaturalKana && git checkout -- . && git pull
```

```sh
cd ~/NaturalKana && python3 tools/bootstrap.py --weights
```

```sh
cd ~/NaturalKana && cp ~/NaturalKana-Brand.json Config/Brand.json && python3 tools/rebrand.py
```

然后从[第 7 步](#第-7-步编译)开始，重新编译和安装。设置和 API 密钥会保留。

> `bootstrap.py` 如果提示 `unexpected revision`，说明新版本换了上游代码的版本。删掉 `~/NaturalKana/upstream` 文件夹后再运行一次上面的 `bootstrap.py`（会重新下载模型），然后继续。

## 卸载

1. 系统设置 → 键盘 → 输入法 → 编辑…，选中 NaturalKana，点 `-` 删除。
2. 终端运行（把 `你的macBundleIdentifier` 换成 `Config/Brand.json` 里的那一项）：

   ```sh
   ID='你的macBundleIdentifier'; launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/$ID.ConverterServer.plist; rm -f ~/Library/LaunchAgents/$ID.ConverterServer.plist; rm -rf ~/Library/Input\ Methods/NaturalKana.app
   ```

3. 不再需要源码的话，删掉 `~/NaturalKana` 文件夹。

## 常见问题

| 现象 | 怎么办 |
| --- | --- |
| `xcrun: error: invalid active developer path` 或找不到 `xcodebuild` | Xcode 没装好，或者装好后没打开过。回到[第 1 步](#第-1-步安装-xcode) |
| `brew: command not found` | Homebrew 装完后没运行它提示的“Next steps”命令。重新打开终端，按 brew.sh 的说明补上 |
| `Install git-lfs and rerun --weights` | 没装 Git LFS，回到[第 2 步](#第-2-步安装-homebrew-和-git-lfs) |
| `macBundleIdentifier must contain ".inputmethod."` | `Config/Brand.json` 里的标识格式不对，按[第 6 步](#第-6-步设置你自己的应用标识)改好后重新运行 `rebrand.py` |
| `json.decoder.JSONDecodeError` | `Brand.json` 里有弯引号或少了逗号。对照第 6 步的示例重新粘贴 |
| `Set your actual Xcode development team ID before a signed build` | 没运行 `export NATURALKANA_TEAM_ID=…`，或者关过终端。重新运行那一行 |
| 编译时提示 `No Account for Team` 或 `No signing certificate` | Xcode 里没登录 Apple ID，或者 Team ID 填错。回到[第 3 步](#第-3-步在-xcode-里登录-apple-id-并创建证书)、[第 4 步](#第-4-步查出你的-team-id)核对 |
| 编译时下载依赖失败、超时 | 网络问题，换个网络或稍后重新运行编译命令 |
| `Unexpected app identity; nothing installed.` | 编译的程序和 `Brand.json` 里的标识对不上，通常是改完标识没重新编译。重新运行第 6 步的 `rebrand.py` 和第 7 步 |
| `A staging app already exists` | 上次安装中断了。删掉提示里那个 `NaturalKana.installing.app` 后重新安装 |
| 系统设置的列表里没有 NaturalKana | 先退出登录再登录。还不行就打开一次输入法列表，然后运行 `log show --last 5m --predicate 'process == "imklaunchagent"' \| grep 'Refusing connection'`，有输出说明标识缺少 `.inputmethod.`，按第 6 步改好后重新编译、安装 |
| 菜单里找不到“NaturalKana 设置…” | 确认当前选中的是 NaturalKana 输入法；或在项目文件夹运行 `zsh tools/open_macos_settings.command` |
| 用了一段时间后输入法突然不工作 | 重新执行[第 7 步](#第-7-步编译)和[第 8 步](#第-8-步安装)即可，设置和密钥不会丢 |
| Intel 芯片的 Mac | 暂不支持 |

还是解决不了，到 [Issues](https://github.com/cyber917/NaturalKana/issues) 提问。写清楚 Mac 型号、macOS 版本、卡在第几步，以及终端里最后 20 行左右的文字。截图前遮住邮箱、Team ID 和 API 密钥。
