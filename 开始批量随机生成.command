#!/bin/bash
set -u

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
tool_dir="$(cd "$(dirname "$0")" && pwd)"
config="$tool_dir/批量生成参数.conf"
live_source="$tool_dir/LivePhotoMaker.swift"
live_plist="$tool_dir/LivePhotoMaker-Info.plist"
live_binary="$tool_dir/LivePhotoMaker"

dialog() {
  if [[ -x /usr/bin/osascript ]]; then
    /usr/bin/osascript -e "display dialog \"$1\" buttons {\"好\"} default button \"好\" with title \"Live Photo 随机组合批量工具\""
  else
    echo "$1"
  fi
}

command -v ffmpeg >/dev/null 2>&1 || { dialog "尚未安装 FFmpeg，请先运行『首次安装.command』。"; exit 1; }
[[ -f "$config" ]] || { dialog "找不到『批量生成参数.conf』。"; exit 1; }
# shellcheck disable=SC1090
source "$config"

VIDEOS_PER_IMAGE="${VIDEOS_PER_IMAGE:-2}"
DURATION="${DURATION:-3}"
FPS="${FPS:-30}"
QUALITY="${QUALITY:-14}"
SUPERSAMPLE="${SUPERSAMPLE:-2}"
VERTICAL_STRETCH_PERCENT="${VERTICAL_STRETCH_PERCENT:-0.5}"
HORIZONTAL_STRETCH_PERCENT="${HORIZONTAL_STRETCH_PERCENT:-0.5}"
SHEAR_PERCENT="${SHEAR_PERCENT:-0.8}"
ROLL_DEGREES="${ROLL_DEGREES:-0.25}"
LENS_BREATHING="${LENS_BREATHING:-0.012}"
GENERATE_LIVE_PHOTO="${GENERATE_LIVE_PHOTO:-1}"
AUTO_IMPORT_TO_PHOTOS="${AUTO_IMPORT_TO_PHOTOS:-1}"
KEEP_MP4="${KEEP_MP4:-1}"

number='^-?[0-9]+([.][0-9]+)?$'
positive='^[0-9]+([.][0-9]+)?$'
integer='^[0-9]+$'
for value in "$VERTICAL_STRETCH_PERCENT" "$HORIZONTAL_STRETCH_PERCENT" \
  "$SHEAR_PERCENT" "$ROLL_DEGREES" "$LENS_BREATHING"; do
  [[ "$value" =~ $number ]] || { dialog "形变参数格式错误，等号右边只能填数字。"; exit 1; }
done
[[ "$VIDEOS_PER_IMAGE" =~ $integer && "$DURATION" =~ $positive && "$FPS" =~ $integer && \
  "$QUALITY" =~ $integer && "$SUPERSAMPLE" =~ $integer ]] || {
  dialog "生成数量、时长、帧率、清晰度或超采样参数格式错误。"; exit 1;
}
(( VIDEOS_PER_IMAGE >= 1 && VIDEOS_PER_IMAGE <= 35 )) || { dialog "VIDEOS_PER_IMAGE 只能设为1～35。"; exit 1; }
for flag in "$GENERATE_LIVE_PHOTO" "$AUTO_IMPORT_TO_PHOTOS" "$KEEP_MP4"; do
  [[ "$flag" == "0" || "$flag" == "1" ]] || { dialog "Live Photo 开关只能填写0或1。"; exit 1; }
done
(( FPS >= 24 && FPS <= 60 && SUPERSAMPLE >= 1 && SUPERSAMPLE <= 4 )) || {
  dialog "FPS 请设为24～60，SUPERSAMPLE 请设为1～4。"; exit 1;
}
if (( GENERATE_LIVE_PHOTO == 0 && KEEP_MP4 == 0 )); then
  dialog "GENERATE_LIVE_PHOTO 和 KEEP_MP4 不能同时设为0，否则不会留下任何成品。"
  exit 1
fi

if [[ -n "${LIVE_MOTION_INPUT_DIR:-}" ]]; then
  input_dir="$LIVE_MOTION_INPUT_DIR"
else
input_dir=$(/usr/bin/osascript <<'APPLESCRIPT'
try
  POSIX path of (choose folder with prompt "选择装有待处理静态图片的文件夹")
on error number -128
  return ""
end try
APPLESCRIPT
)
fi
[[ -n "$input_dir" ]] || exit 0

shopt -s nullglob nocaseglob
files=("$input_dir"/*.jpg "$input_dir"/*.jpeg "$input_dir"/*.png "$input_dir"/*.heic "$input_dir"/*.webp)
(( ${#files[@]} > 0 )) || { dialog "所选文件夹里没有 JPG、PNG、HEIC 或 WebP 图片。"; exit 1; }

frames=$(/usr/bin/awk -v d="$DURATION" -v f="$FPS" 'BEGIN {printf "%d", d*f}')
(( frames >= 2 )) || { dialog "DURATION 设置得太短。"; exit 1; }
last=$((frames - 1))
work_w=$((1080 * SUPERSAMPLE))
work_h=$((1920 * SUPERSAMPLE))
u="on/${last}"
p="(${u})*(${u})*(3-2*${u})"
settle="(1-exp(-4*${u}))/(1-exp(-4))"
phase="sin(PI*t/${DURATION})"

vstretch=$(/usr/bin/awk -v v="$VERTICAL_STRETCH_PERCENT" 'BEGIN {printf "%.8f", v/100}')
hstretch=$(/usr/bin/awk -v v="$HORIZONTAL_STRETCH_PERCENT" 'BEGIN {printf "%.8f", v/100}')
shear=$(/usr/bin/awk -v v="$SHEAR_PERCENT" 'BEGIN {printf "%.8f", v/100}')
roll=$(/usr/bin/awk -v v="$ROLL_DEGREES" 'BEGIN {printf "%.8f", v*3.141592653589793/180}')

camera_names=(
  "01-v1.3手持基准" "02-v1.3快门基准" "03-柔和手持" "04-稳定推近"
  "05-轻微上提" "06-轻微下压" "07-轻微左漂"
)
camera_z=(
  "1+0.08*(0.15+0.85*${p})"
  "1+0.04*(0.12+0.88*${settle})"
  "1+0.075*(0.15+0.85*${p})"
  "1+0.075*${p}" "1+0.075*${p}" "1+0.075*${p}" "1+0.075*${p}"
)
camera_x=(
  "0.016*iw*(0.60*${p}+0.50*sin(PI*${p}))"
  "0.008*iw*(${settle}+0.10*sin(4*PI*${u})*(1-${u}))"
  "0.012*iw*(0.82*${p}+0.16*sin(PI*${p}))"
  "0" "0.005*iw*${p}" "0.005*iw*${p}" "-0.009*iw*${p}"
)
camera_y=(
  "0.005*ih*(0.55*${p}+0.35*sin(2*PI*${p}))"
  "0.0025*ih*(0.70*${settle}+0.08*sin(3*PI*${u})*(1-${u}))"
  "0.003*ih*(0.78*${p}+0.07*sin(2*PI*${p}))"
  "0" "-0.0035*ih*${p}" "0.0035*ih*${p}" "0.0015*ih*${p}"
)
shape_names=("01-纵向形变" "02-横向形变" "03-仿射倾斜" "04-轻微侧倾" "05-镜头畸变呼吸")

stamp=$(/bin/date +%Y%m%d-%H%M%S)
output_dir="${input_dir%/}/随机微动视频-${stamp}"
/bin/mkdir -p "$output_dir"
mp4_output_dir="$output_dir/MP4视频"
live_output_dir="$output_dir/LivePhoto配对文件"
(( KEEP_MP4 == 1 )) && /bin/mkdir -p "$mp4_output_dir"
if (( GENERATE_LIVE_PHOTO == 1 )); then
  [[ -f "$live_source" && -f "$live_plist" ]] || { dialog "缺少 LivePhotoMaker.swift 或 Info.plist，请完整更新仓库。"; exit 1; }
  command -v xcrun >/dev/null 2>&1 || { dialog "缺少 Apple Command Line Tools，请先执行 xcode-select --install。"; exit 1; }
  if [[ ! -x "$live_binary" || "$live_source" -nt "$live_binary" || "$live_plist" -nt "$live_binary" ]]; then
    compile_log="$tool_dir/LivePhotoMaker-编译日志.txt"
    if ! xcrun swiftc -swift-version 5 "$live_source" -o "$live_binary" \
      -framework AVFoundation -framework ImageIO -framework Photos \
      -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$live_plist" \
      >"$compile_log" 2>&1; then
      /usr/bin/open -a TextEdit "$compile_log"
      dialog "Live Photo 助手编译失败，日志已用文本编辑打开。"
      exit 1
    fi
    /bin/rm -f "$compile_log"
  fi
  /bin/mkdir -p "$live_output_dir"
fi
temp_dir=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/random-live-motion.XXXXXX") || {
  dialog "无法创建临时处理目录。"; exit 1;
}
[[ -n "$temp_dir" && -d "$temp_dir" ]] || { dialog "临时处理目录异常。"; exit 1; }
trap '/bin/rm -rf "$temp_dir"' EXIT

render_camera() {
  local cam="$1" prepared="$2" camera_file="$3"
  [[ -f "$camera_file" ]] && return 0
  local zexpr="${camera_z[$cam]}" xmove="${camera_x[$cam]}" ymove="${camera_y[$cam]}"
  local xexpr="min(max(iw/2-(iw/zoom/2)+${xmove},0),iw-iw/zoom)"
  local yexpr="min(max(ih/2-(ih/zoom/2)+${ymove},0),ih-ih/zoom)"
  # 全程保留超采样分辨率和 4:4:4 色彩；中间文件无损，避免形变前后重复压缩。
  local filter="scale=${work_w}:${work_h}:force_original_aspect_ratio=increase:flags=lanczos,crop=${work_w}:${work_h},zoompan=z='${zexpr}':x='${xexpr}':y='${yexpr}':d=${frames}:s=${work_w}x${work_h}:fps=${FPS},format=yuv444p"
  ffmpeg -hide_banner -loglevel error -y -i "$prepared" -vf "$filter" -frames:v "$frames" -an \
    -c:v libx264 -preset medium -crf 0 -pix_fmt yuv444p "$camera_file"
}

render_combo() {
  local camera_file="$1" shape="$2" target="$3" filter
  case "$shape" in
    0) filter="perspective=x0=0:y0='-H*${vstretch}/2*sin(PI*in/${last})':x1=W:y1='-H*${vstretch}/2*sin(PI*in/${last})':x2=0:y2='H*(1+${vstretch}/2*sin(PI*in/${last}))':x3=W:y3='H*(1+${vstretch}/2*sin(PI*in/${last}))':sense=destination:eval=frame:interpolation=cubic,scale=1080:1920:flags=lanczos" ;;
    1) filter="scale=w='trunc(iw*(1+${hstretch}*${phase})/2)*2':h=ih:eval=frame,crop=${work_w}:${work_h}:(in_w-out_w)/2:(in_h-out_h)/2,scale=1080:1920:flags=lanczos" ;;
    2) filter="scale=$((work_w+88*SUPERSAMPLE)):$((work_h+158*SUPERSAMPLE)):flags=lanczos,sendcmd=c='0-${DURATION} [expr] shear@warp shx ${shear}*sin(PI*TI)',shear@warp=shx=0:shy=0:fillcolor=black:interp=bilinear,crop=${work_w}:${work_h}:(in_w-out_w)/2:(in_h-out_h)/2,scale=1080:1920:flags=lanczos" ;;
    3) filter="scale=$((work_w+88*SUPERSAMPLE)):$((work_h+158*SUPERSAMPLE)):flags=lanczos,rotate=angle='${roll}*sin(PI*t/${DURATION})':fillcolor=black:bilinear=1,crop=${work_w}:${work_h}:(in_w-out_w)/2:(in_h-out_h)/2,scale=1080:1920:flags=lanczos" ;;
    4) filter="scale=$((work_w+110*SUPERSAMPLE)):$((work_h+196*SUPERSAMPLE)):flags=lanczos,sendcmd=c='0-${DURATION} [expr] lenscorrection@lens k1 ${LENS_BREATHING}*sin(PI*TI)',lenscorrection@lens=cx=0.5:cy=0.5:k1=0:k2=0:i=bilinear:fc=black,crop=${work_w}:${work_h}:(in_w-out_w)/2:(in_h-out_h)/2,scale=1080:1920:flags=lanczos" ;;
    *) return 1 ;;
  esac
  ffmpeg -hide_banner -loglevel error -y -i "$camera_file" -vf "$filter,format=yuv420p" \
    -frames:v "$frames" -an -c:v libx264 -preset slow -crf "$QUALITY" \
    -movflags +faststart "$target"
}

success=0
failed=0
live_success=0
live_failed=0
image_index=0
total_images=${#files[@]}

for src in "${files[@]}"; do
  image_index=$((image_index + 1))
  printf -v sequence "%03d" "$image_index"
  base=$(/usr/bin/basename "$src")
  name="${base%.*}"
  image_temp="$temp_dir/image-$sequence"
  /bin/mkdir -p "$image_temp"
  prepared="$image_temp/source.jpg"

  echo "[$image_index/$total_images] 正在处理：$base"
  if [[ -x /usr/bin/sips ]]; then
    /usr/bin/sips -s format jpeg "$src" --out "$prepared" >/dev/null 2>&1
    converted=$?
  else
    ffmpeg -hide_banner -loglevel error -y -i "$src" -frames:v 1 "$prepared"
    converted=$?
  fi
  if (( converted != 0 )); then
    echo "  图片无法读取，已跳过。"
    failed=$((failed + VIDEOS_PER_IMAGE))
    continue
  fi

  selected=" "
  selected_count=0
  while (( selected_count < VIDEOS_PER_IMAGE )); do
    combo=$((RANDOM % 35))
    case "$selected" in
      *" $combo "*) ;;
      *) selected="$selected$combo "; selected_count=$((selected_count + 1)) ;;
    esac
  done

  for combo in $selected; do
    shape=$((combo / 7))
    cam=$((combo % 7))
    camera_file="$image_temp/camera-$cam.mkv"
    file_stem="${sequence}-${name}-${shape_names[$shape]}+${camera_names[$cam]}"
    if (( KEEP_MP4 == 1 )); then
      target="$mp4_output_dir/${file_stem}.mp4"
    else
      target="$image_temp/${file_stem}.mp4"
    fi
    echo "  → ${shape_names[$shape]} + ${camera_names[$cam]}"
    if render_camera "$cam" "$prepared" "$camera_file" && render_combo "$camera_file" "$shape" "$target"; then
      success=$((success + 1))
      if (( GENERATE_LIVE_PHOTO == 1 )); then
        live_args=("$src" "$target" "$live_output_dir")
        (( AUTO_IMPORT_TO_PHOTOS == 1 )) && live_args+=("--import")
        if "$live_binary" "${live_args[@]}"; then
          live_success=$((live_success + 1))
          # KEEP_MP4=0 时 target 位于临时目录，任务结束自动清理。
        else
          live_failed=$((live_failed + 1))
          if (( KEEP_MP4 == 0 )); then
            /bin/mkdir -p "$mp4_output_dir"
            /bin/mv "$target" "$mp4_output_dir/${file_stem}.mp4"
          fi
          echo "  Live Photo 制作或导入失败，MP4和配对文件均已保留。"
        fi
      fi
    else
      failed=$((failed + 1))
    fi
  done
done

[[ "$(/usr/bin/uname -s)" == "Darwin" && -x /usr/bin/open ]] && /usr/bin/open "$output_dir"
if (( GENERATE_LIVE_PHOTO == 1 )); then
  dialog "处理完成：MP4成功${success}条、失败${failed}条；Live Photo成功${live_success}条、失败${live_failed}条。"
elif (( failed == 0 )); then
  dialog "完成：${total_images}张图，每张${VIDEOS_PER_IMAGE}条，共生成${success}条随机组合视频。"
else
  dialog "处理结束：成功${success}条，失败${failed}条。请保留终端报错截图。"
fi
