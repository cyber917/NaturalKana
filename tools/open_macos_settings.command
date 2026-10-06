#!/bin/zsh
set -eu
app="$HOME/Library/Input Methods/NaturalKana.app"
if [[ ! -d "$app" ]]; then
  print '请先安装 NaturalKana 系统输入法。'
  exit 1
fi
/usr/bin/open "$app" --args --natural-settings
