#!/bin/bash
set -u

tool_dir="$(cd "$(dirname "$0")" && pwd)"
source_file="$tool_dir/LivePhotoMaker.swift"
info_plist="$tool_dir/LivePhotoMaker-Info.plist"
binary="$tool_dir/LivePhotoMaker"

dialog() {
  /usr/bin/osascript -e "display dialog \"$1\" buttons {\"好\"} default button \"好\" with title \"Live Photo 单张验收\""
}

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || { echo "此工具只能在 macOS 上运行。"; exit 1; }
[[ -f "$source_file" && -f "$info_plist" ]] || { dialog "缺少 LivePhotoMaker.swift 或 Info.plist。请完整下载仓库。"; exit 1; }
command -v xcrun >/dev/null 2>&1 || { dialog "缺少 Apple Command Line Tools。请先在终端执行：xcode-select --install"; exit 1; }

if [[ ! -x "$binary" || "$source_file" -nt "$binary" || "$info_plist" -nt "$binary" ]]; then
  echo "首次运行：正在编译 Live Photo 助手……"
  xcrun swiftc "$source_file" -o "$binary" \
    -framework AVFoundation -framework ImageIO -framework Photos \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$info_plist" || {
      dialog "编译失败。请保留终端完整报错截图。"
      exit 1
    }
fi

photo=$(/usr/bin/osascript <<'APPLESCRIPT'
try
  POSIX path of (choose file with prompt "第一步：选择原始静态图片")
on error number -128
  return ""
end try
APPLESCRIPT
)
[[ -n "$photo" ]] || exit 0

movie=$(/usr/bin/osascript <<'APPLESCRIPT'
try
  POSIX path of (choose file with prompt "第二步：选择这张图片生成的 MP4 视频")
on error number -128
  return ""
end try
APPLESCRIPT
)
[[ -n "$movie" ]] || exit 0

stamp=$(/bin/date +%Y%m%d-%H%M%S)
output_dir="$(/usr/bin/dirname "$photo")/LivePhoto测试-${stamp}"
/bin/mkdir -p "$output_dir"

echo "正在制作并导入 Live Photo……"
if "$binary" "$photo" "$movie" "$output_dir" --import; then
  /usr/bin/open "$output_dir"
  /usr/bin/open -a Photos
  dialog "已生成 JPG+MOV 配对文件，并已请求导入『照片』App。请在照片中确认是否显示 LIVE 标志、长按是否能播放。"
else
  dialog "制作失败。请把终端最后的 ERROR 行截图发来。原始图片和 MP4 不会被修改。"
  exit 1
fi
