# NaturalKana

[English](README.en.md)

日语输入与表达建议，支持 macOS 输入法和 iPhone 键盘。

- Qwen / 百炼、OpenAI、DeepSeek、Kimi、Gemini、Claude，以及自定义兼容接口。
- 口语和敬语分组，最多 10 条建议。
- iPhone 顶部候选卡片，左右翻页；Mac 使用独立候选窗。
- 支持个人词库参考，保留原句中的网络用语。
- 日语里夹杂不熟悉的英文、中文词语时，也可获取日语建议。
- 本地标出候选中的改动，不额外调用模型。

## 项目状态

当前为开发版。源码已在 macOS 与 iPhone 上构建和使用；不同应用、设备和系统版本仍需测试。目前提供源码，自行构建安装。

## 使用

在应用设置中填写服务商、模型和 API 密钥，允许发送当前句子并开启建议。
模型填写服务商 API 的模型 ID，不能填应用里的展示名称。每家服务商分别保存配置和密钥。“接口兼容”可调整协议、JSON 格式和输出参数；自定义接口支持 OpenAI 兼容和 Claude Messages。

iPhone 还需在系统的键盘设置中添加 NaturalKana，开启“允许完全访问”。
建议出现后，点击句子采用；iPhone 上左右切换候选，右上角关闭。
Mac 默认使用 Control + 1 / 2 采用前两条候选，Esc 关闭建议。
小勾表示模型认为无需修改，转圈表示正在检查，叹号表示请求失败。iPhone 点图标、Mac 悬停可查看详情。状态判断使用同一次请求，不额外调用模型。

## 构建

需要 Xcode、Git 和 Git LFS。

```sh
git clone https://github.com/cyber917/NaturalKana.git
cd NaturalKana
python3 tools/bootstrap.py --weights
open NaturalKana.xcworkspace
```

在 Xcode 中配置自己的签名账户。iPhone 的 scheme 为 `MainApp`，主应用和 `Keyboard` 扩展使用同一 Team、App Group 和钥匙串组。
建议选择 Release 配置进行设备测试。

`Config/Brand.json` 保存公开的默认标识。需要自定义时，修改它并运行 `python3 tools/rebrand.py`，再重新签名构建。
已安装版本应保持原有标识，否则无法沿用原来的设置和密钥。

## 隐私

联网建议发送当前句子（最多 200 字）、表达偏好和命中的词库参考。API 密钥保存在设备钥匙串。
双模型评选会向两家服务商发送请求；服务商的数据政策仍然适用。
不要把自己的密钥、导入词库、签名证书或已签名应用提交到仓库。

## 开发与验证

```sh
swift test --package-path NaturalSuggestCore
python3 tools/check_public_source.py
```

本地身份配置可保存在被 Git 忽略的 `Config/LocalBrand.json`。导出上游修改使用 `tools/export_patches.py`，公开补丁使用通用标识并移除签名 Team。
`upstream/` 是本地工作目录；仓库通过固定版本和 `patches/` 重建，不直接上传它。

iPhone 候选仅在输入框末尾提供安全替换；不同宿主应用的键盘兼容性仍需测试。
Mac 无法核验鼠标替换范围时会复制建议，提示选中原句粘贴。

## 许可

基于 azooKey 的输入引擎与界面组件。项目许可、上游许可与依赖说明见 `LICENSE`、`licenses/` 和 `THIRD_PARTY_NOTICES.md`。
