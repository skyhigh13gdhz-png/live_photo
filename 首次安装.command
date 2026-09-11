#!/bin/bash
set -u

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

show_message() {
  /usr/bin/osascript -e "display dialog \"$1\" buttons {\"好\"} default button \"好\" with title \"丝滑微动视频工具\""
}

if command -v ffmpeg >/dev/null 2>&1; then
  show_message "FFmpeg 已经安装，可以直接右键打开『开始批量生成.command』。"
  exit 0
fi

if ! command -v brew >/dev/null 2>&1; then
  show_message "电脑尚未安装 Homebrew。接下来终端会安装它，过程中可能要求输入 Mac 开机密码；输入时屏幕不会显示字符。"
  /bin/bash -c "$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
    show_message "Homebrew 安装没有完成。请检查网络后重新运行。"
    exit 1
  }
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
fi

brew install ffmpeg || {
  show_message "FFmpeg 安装失败。请检查网络后重新运行。"
  exit 1
}

show_message "安装完成。以后只需右键打开『开始批量生成.command』。"
