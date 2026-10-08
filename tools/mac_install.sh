#!/bin/bash
# One-step install / update of the NaturalKana macOS input method for non-developers.
#   bash <(curl -fsSL https://raw.githubusercontent.com/cyber917/NaturalKana/main/tools/mac_install.sh)
# Run it again later to update. Options: --no-install (build only).
# Your identity is kept in ~/.config/naturalkana/Brand.json so updates reuse it.
set -euo pipefail

REPO_URL="https://github.com/cyber917/NaturalKana.git"
DIR="${NATURALKANA_DIR:-$HOME/NaturalKana}"
BRAND_FILE="${NATURALKANA_BRAND_FILE:-$HOME/.config/naturalkana/Brand.json}"
INSTALL=1
[[ "${1:-}" == "--no-install" ]] && INSTALL=0

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
info() { printf '    %s\n' "$1"; }
fail() { printf '\n\033[1;31m✗ %s\033[0m\n' "$1" >&2; shift; for line in "$@"; do printf '    %s\n' "$line" >&2; done; exit 1; }
ask() { local answer; read -r -p "    $1" answer < /dev/tty; printf '%s' "$answer"; }
pause() { read -r -p "    $1（准备好后按回车）" _ < /dev/tty; }

step "检查这台 Mac"
[[ "$(uname -m)" == "arm64" ]] || fail "只支持 Apple 芯片（M1、M2……）的 Mac，这台是 Intel 芯片。"
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 13 )) || fail "需要 macOS 13 或更新，当前是 $(sw_vers -productVersion)。"
info "Apple 芯片，macOS $(sw_vers -productVersion) ✓"

step "检查 Xcode"
XCODE="${NATURALKANA_XCODE:-/Applications/Xcode.app}"
if [[ ! -d "$XCODE" ]]; then
  XCODE="$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null | head -n 1)"
fi
[[ -n "$XCODE" && -d "$XCODE" ]] || fail "没有找到 Xcode。" "请先在 App Store 安装 Xcode，打开一次并同意协议，然后重新运行这个脚本。"
export DEVELOPER_DIR="$XCODE/Contents/Developer"
XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"
if ! "$XCODEBUILD" -license check >/dev/null 2>&1; then
  info "需要同意 Xcode 许可协议，请输入开机密码（输入时不显示字符）。"
  sudo "$XCODEBUILD" -license accept
fi
if ! "$XCODEBUILD" -checkFirstLaunchStatus >/dev/null 2>&1; then
  info "正在安装 Xcode 附加组件，请输入开机密码。"
  sudo "$XCODEBUILD" -runFirstLaunch
fi
info "$XCODE ✓"

step "检查 Git LFS"
# Needed for the model downloads, and git itself fails on the LFS files once the filter is configured.
# Homebrew is often installed but not on PATH when its "Next steps" were skipped.
if ! command -v brew >/dev/null 2>&1 && [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
if ! git lfs version >/dev/null 2>&1; then
  command -v brew >/dev/null 2>&1 || fail "需要 Git LFS，但这台 Mac 没有 Homebrew。" \
    "到 https://brew.sh/zh-cn/ 安装 Homebrew（装完照它提示的 Next steps 运行），再重新运行这个脚本。"
  info "正在用 Homebrew 安装 Git LFS……"
  brew install git-lfs >/dev/null || fail "安装 Git LFS 失败，检查网络后重试。"
fi
git lfs install >/dev/null
info "$(git lfs version | cut -d' ' -f1) ✓"

step "查找你的 Team ID"
identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp:?}"' EXIT
security find-certificate -a -c "Apple Development" -p 2>/dev/null \
  | awk -v dir="$tmp" '/BEGIN CERTIFICATE/{n++} n{print > (dir "/cert" n ".pem")}' || true
teams=""
for pem in "$tmp"/cert*.pem; do
  [[ -f "$pem" ]] || continue
  sha1="$(openssl x509 -noout -fingerprint -sha1 -in "$pem" | sed 's/.*=//; s/://g')"
  grep -q "$sha1" <<< "$identities" || continue  # skip expired certificates or ones without a private key
  team="$(openssl x509 -noout -subject -in "$pem" | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p')"
  [[ -n "$team" ]] && teams="$teams$team"$'\n'
done
teams="$(printf '%s' "$teams" | sort -u | sed '/^$/d')"
if [[ -z "$teams" ]]; then
  # Tell apart "no certificate", "not trusted" (missing Apple intermediate) and "private key not on this Mac".
  found=0; for pem in "$tmp"/cert*.pem; do [[ -f "$pem" ]] && found=$((found + 1)); done
  (( found > 0 )) || fail "没有找到开发证书。" \
    "打开 Xcode → Settings → Accounts，点 + 登录 Apple ID；" \
    "选中账号 → Manage Certificates → 点 + → Apple Development → Done。然后重新运行这个脚本。"
  if security find-identity -p codesigning 2>/dev/null | grep "Apple Development" | grep -q "NOT_TRUSTED"; then
    fail "找到了开发证书，但系统还不信任它（这台 Mac 缺少苹果的中间证书）。" \
      "用浏览器打开 https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer 下载，" \
      "双击下载的文件，钥匙串选“登录”，点“添加”。然后重新运行这个脚本。"
  fi
  fail "找到了开发证书，但它的私钥不在这台 Mac 上（证书可能是在别的电脑上创建的，或已过期）。" \
    "打开 Xcode → Settings → Accounts → 选中账号 → Manage Certificates，" \
    "点 + → Apple Development 在这台 Mac 上再创建一个，然后重新运行这个脚本。"
fi
if [[ "$(wc -l <<< "$teams" | tr -d ' ')" == 1 ]]; then
  TEAM="$teams"
else
  info "找到多个 Team："
  i=0; while read -r t; do i=$((i + 1)); info "  $i) $t"; done <<< "$teams"
  choice="$(ask "选择要用的编号：")"
  TEAM="$(sed -n "${choice}p" <<< "$teams")"
  [[ -n "$TEAM" ]] || fail "编号无效。"
fi
info "Team ID：$TEAM ✓"

step "准备源码"
if [[ -d "$DIR/.git" ]]; then
  cd "$DIR"
  [[ ! -f Config/LocalBrand.json ]] || fail "检测到 Config/LocalBrand.json（开发者配置），这个脚本不处理这种环境。"
  info "已有源码：${DIR}，更新到最新版"
  allowed=$'Config/Brand.json\nConfig/GeneratedBrand.json\npatches/ios.patch\npatches/macos.patch'
  unexpected="$(git status --porcelain --untracked-files=no | cut -c4- | grep -vxF "$allowed" || true)"
  [[ -z "$unexpected" ]] || fail "源码里有你自己改过的文件，为避免覆盖，脚本已停止：" $unexpected
  for d in upstream/azooKey-macos upstream/azooKey-ios; do
    if [[ -d "$d/.git" || -f "$d/.git" ]]; then git -C "$d" checkout -q -- . && git -C "$d" clean -qfd; fi
  done
  git checkout -q -- .
  git pull -q --ff-only || fail "更新源码失败。" "检查网络后重试；仍然失败请到 Issues 提问。"
else
  [[ ! -e "$DIR" ]] || fail "$DIR 已存在但不是 NaturalKana 源码文件夹。" "请改名或移走它后重新运行。"
  info "下载到 $DIR"
  git clone -q "$REPO_URL" "$DIR" || fail "下载源码失败，检查网络后重试。"
  cd "$DIR"
fi

step "下载上游源码和模型（第一次需要十几分钟）"
log_dir="$DIR/.build-local"; mkdir -p "$log_dir"
if ! python3 tools/bootstrap.py >"$log_dir/bootstrap.log" 2>&1; then
  if grep -q "unexpected revision" "$log_dir/bootstrap.log"; then
    fail "新版本换了上游代码的版本，需要重新下载。" "删除 $DIR/upstream 文件夹后重新运行这个脚本。"
  fi
  tail -n 20 "$log_dir/bootstrap.log" >&2
  fail "准备上游源码失败，完整记录：$log_dir/bootstrap.log"
fi
if ! python3 tools/verify_mac_models.py >/dev/null 2>&1; then
  python3 tools/bootstrap.py --weights >>"$log_dir/bootstrap.log" 2>&1 \
    || { tail -n 20 "$log_dir/bootstrap.log" >&2; fail "下载模型失败，完整记录：$log_dir/bootstrap.log"; }
  python3 tools/verify_mac_models.py >/dev/null || fail "模型文件不完整，请检查网络后重新运行。"
fi
info "上游源码和模型 ✓"

step "设置你的应用标识"
if [[ -f "$BRAND_FILE" ]]; then
  info "沿用之前的标识：$BRAND_FILE"
  saved_team="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["macAppGroup"].split(".")[0])' "$BRAND_FILE")"
  [[ "$saved_team" == "$TEAM" ]] || fail "之前的标识属于 Team ${saved_team}，这次找到的是 ${TEAM}。" \
    "如果确实要换账号，删除 $BRAND_FILE 后重新运行（会被系统当成另一个输入法，设置要重新填写）。"
else
  default_name="$(id -un | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
  [[ -n "$default_name" ]] || default_name="user"
  name="$(ask "输入一个英文名，只用小写字母和数字（直接回车用 ${default_name}）：")"
  name="${name:-$default_name}"
  [[ "$name" =~ ^[a-z][a-z0-9]{1,30}$ ]] || fail "名字只能用小写字母开头，后面跟小写字母或数字。"
  mkdir -p "$(dirname "$BRAND_FILE")"
  python3 - "$BRAND_FILE" "$name" "$TEAM" <<'PY'
import json, sys
path, name, team = sys.argv[1:]
mac = f"com.{name}.inputmethod.naturalkana.mac"
json.dump({"name": "NaturalKana", "bundlePrefix": f"com.{name}.naturalkana", "iosAppGroup": f"group.com.{name}.naturalkana",
           "macAppGroup": f"{team}.{mac}", "macBundleIdentifier": mac}, open(path, "w"), indent=2)
PY
  info "标识已保存到 ${BRAND_FILE}，以后更新会自动沿用"
fi
cp "$BRAND_FILE" Config/Brand.json
python3 tools/rebrand.py >"$log_dir/rebrand.log" 2>&1 || { cat "$log_dir/rebrand.log" >&2; fail "应用标识设置失败。"; }
MAC_ID="$(python3 -c 'import json; print(json.load(open("Config/Brand.json"))["macBundleIdentifier"])')"
info "$MAC_ID ✓"

step "编译（第一次通常 10～30 分钟，请耐心等待）"
info "如果弹出窗口询问能否使用钥匙串里的证书，输入开机密码并选“始终允许”。"
build() { NATURALKANA_TEAM_ID="$TEAM" bash tools/build_macos.sh --signed >"$log_dir/build.log" 2>&1; }
build_failed() {
  grep -E "error:|requires a provisioning|No Account|No signing" "$log_dir/build.log" | sort -u | head -n 10 >&2 || true
  tail -n 15 "$log_dir/build.log" >&2
  fail "编译失败，完整记录：$log_dir/build.log" "提问时请附上上面这些文字。"
}
if ! build; then
  grep -q "was compiled with module cache path" "$log_dir/build.log" || build_failed
  info "编译缓存来自旧的文件夹位置，清理后重新编译……"  # the source folder was moved
  rm -rf "${log_dir:?}/macos"
  build || build_failed
fi
APP="$log_dir/macos/native/Build/Products/Release/azooKeyMac.app"
info "编译完成 ✓"

if (( INSTALL == 0 )); then
  step "已按 --no-install 跳过安装"
  info "编译结果：$APP"
  exit 0
fi

step "安装"
pause "请先把当前输入法切换成系统自带的（例如“ABC”或“简体拼音”）。"
mkdir -p "$log_dir/bin"
xcrun swiftc tools/register_input_source.swift -o "$log_dir/bin/register-input-source"
python3 tools/install_macos.py --app "$APP" --registrar "$log_dir/bin/register-input-source" \
  || fail "安装失败。" "如果提示 Existing destination is another app，说明已经装过另一个标识的 NaturalKana，先按教程的“卸载”删掉旧版。"

step "完成 🎉"
info "接下来："
info "1. 在打开的“键盘”设置里：输入法 → 编辑… → 点 + → 日语 → 添加 NaturalKana"
info "   列表里没有的话，先退出登录再登录一次。"
info "2. 菜单栏输入法图标 → NaturalKana 设置… → 表达建议，填写服务商和 API 密钥"
info "以后要更新，重新运行同一条命令即可，设置和密钥会保留。"
open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension" 2>/dev/null || true
