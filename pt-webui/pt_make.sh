#!/bin/bash
# 描述: PT 制种引擎 V9.8.14 (内存闪拼版: /dev/shm 内存盘加速 + 零冗余解码)

export LANG=zh_CN.UTF-8
CONFIG_FILE="$HOME/.pt_make_config"

if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; else ENABLE_GIF="false"; echo "ENABLE_GIF=\"$ENABLE_GIF\"" > "$CONFIG_FILE"; fi

[ -n "$CUSTOM_ENABLE_GIF" ] && ENABLE_GIF="$CUSTOM_ENABLE_GIF"
ENABLE_GIF=$(echo "$ENABLE_GIF" | tr -d ' ' | tr -d '\r' | tr -d '\n')

if [[ "$1" != "--folder" ]] && [[ "$1" != "--auto" ]]; then
    SCRIPT_REAL_PATH="$(readlink -f "$0")"
    if [ "$SCRIPT_REAL_PATH" != "/usr/local/bin/p" ]; then
        cp "$SCRIPT_REAL_PATH" /usr/local/bin/p 2>/dev/null
        chmod +x /usr/local/bin/p 2>/dev/null
        USER_PROFILE="$HOME/.bashrc"
        sed -i '/alias p=/d' "$USER_PROFILE" 2>/dev/null
        echo "alias p='/usr/local/bin/p'" >> "$USER_PROFILE"
    fi
fi

if [ -d "/vol3/1000/downloads" ]; then 
    BASE_DIR="/vol3/1000/downloads"
elif [ -f "/.dockerenv" ]; then 
    BASE_DIR="${BASE_DIR:-/downloads}"
else 
    BASE_DIR="/home/docker/qbittorrent/downloads"
fi

DEFAULT_TRACKER="https://rousi.pro/tracker/808263a94ed47ca690395ca957b562e4/announce"

# 🚀 极限优化 1：强制使用 Linux 内存盘 (/dev/shm) 代替物理硬盘 (/tmp)，IO 速度暴增百倍！
if [ -d "/dev/shm" ]; then
    TMP_ROOT="/dev/shm/pt_make_$(date +%s)"
else
    TMP_ROOT="/tmp/pt_make_$(date +%s)"
fi

FONT_DIR="$BASE_DIR/.config"
FONT_FILE="$FONT_DIR/LXGWWenKaiLite-Regular.ttf"

trap 'rm -rf "$TMP_ROOT"; exit' INT TERM EXIT

check_env() {
    local missing=(); for tool in ffmpeg ffprobe mediainfo mktorrent curl; do command -v "$tool" >/dev/null 2>&1 || missing+=("$tool"); done
    if [ ${#missing[@]} -gt 0 ]; then sudo apt-get update && sudo apt-get install -y "${missing[@]}"; fi
    local VALID_FONT=false
    [ -s "$FONT_FILE" ] && [ "$(du -k "$FONT_FILE" | cut -f1)" -gt 4000 ] && VALID_FONT=true
    if [ "$VALID_FONT" = false ]; then
        mkdir -p "$FONT_DIR"
        local FONT_URLS=("https://mirror.ghproxy.com/https://github.com/lxgw/LxgwWenKai-Lite/releases/download/v1.330/LXGWWenKaiLite-Regular.ttf" "https://github.com/lxgw/LxgwWenKai-Lite/releases/download/v1.330/LXGWWenKaiLite-Regular.ttf")
        for url in "${FONT_URLS[@]}"; do
            curl -f --connect-timeout 15 -m 60 -L "$url" -o "${FONT_FILE}.tmp" 2>/dev/null
            if [ -s "${FONT_FILE}.tmp" ] && [ "$(du -k "${FONT_FILE}.tmp" | cut -f1)" -gt 4000 ]; then mv "${FONT_FILE}.tmp" "$FONT_FILE"; VALID_FONT=true; break; fi
        done
    fi
}
check_env

process_target() {
    local TARGET_NAME="$1"
    local ACTION_TYPE="$2"
    local TARGET_PATH="$BASE_DIR/$TARGET_NAME"
    
    if [[ "$TARGET_NAME" == *.torrent ]] || [[ "$TARGET_NAME" == *_mediainfo.txt ]] || [[ "$TARGET_NAME" == *_Stitched_4K.webp ]] || [[ "$TARGET_NAME" == *_Preview.webp ]] || [[ "$TARGET_NAME" == *_ffmpeg_debug.log ]] || [[ "$TARGET_NAME" == header* ]]; then return; fi
    if [[ ! -e "$TARGET_PATH" ]]; then return; fi

    local BASE_NAME=""; local IS_FILE=false
    if [ -f "$TARGET_PATH" ]; then
        local ext="${TARGET_NAME##*.}"
        [[ ! "${ext,,}" =~ ^(mp4|mkv|avi|wmv|ts)$ ]] || [[ "$TARGET_NAME" == *".!qB" ]] && return
        IS_FILE=true; BASE_NAME="${TARGET_NAME%.*}"
    elif [ -d "$TARGET_PATH" ]; then
        if find "$TARGET_PATH" -type f -name "*.!qB" | grep -q .; then return; fi
        BASE_NAME="$TARGET_NAME"
        
        if [ -z "$ACTION_TYPE" ]; then
            find "$TARGET_PATH" -type f \( -iname "*.url" -o -iname "*.txt" -o -iname "*.nfo" -o -iname "*.log" \) -delete > /dev/null 2>&1
            for vf in "$TARGET_PATH"/*; do
                if [[ -f "$vf" ]]; then
                    local vext="${vf##*.}"
                    if [[ "${vext,,}" =~ ^(mp4|mkv|avi|wmv|ts)$ ]]; then
                        [ "$(du -k "$vf" | cut -f1)" -lt 256000 ] && rm -f "$vf" && continue
                    fi
                    local fname=$(basename "$vf")
                    [[ "$fname" == *"@"* ]] && mv "$vf" "$TARGET_PATH/${fname#*@}"
                fi
            done
        else
            echo "🛡️ [安全锁激活] 单项微操指令 ($ACTION_TYPE)，跳过清理确保 Hash 安全。"
        fi
    else return; fi

    local TORRENT_FILE="$BASE_DIR/${BASE_NAME}.torrent"
    local INFO_FILE="$BASE_DIR/${BASE_NAME}_mediainfo.txt"
    local STITCHED_IMG="$BASE_DIR/${BASE_NAME}_Stitched_4K.webp"
    local PREVIEW_WEBP="$BASE_DIR/${BASE_NAME}_Preview.webp"
    local TMP_IMG_DIR="$TMP_ROOT/$BASE_NAME"

    echo "------------------------------------------------"
    echo "📦 锁定任务: $TARGET_NAME | 执行指令: ${ACTION_TYPE:-完整流水线}"

    local VIDEO_FILES=(); if [ "$IS_FILE" = true ]; then VIDEO_FILES=("$TARGET_PATH"); else mapfile -t VIDEO_FILES < <(find "$TARGET_PATH" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.wmv" -o -iname "*.ts" \) | sort); fi
    [ ${#VIDEO_FILES[@]} -eq 0 ] && return
    local MAIN_VIDEO="${VIDEO_FILES[0]}"
    
    if [ -z "$ACTION_TYPE" ] || [ "$ACTION_TYPE" == "--only-torrent" ]; then
        if [ ! -f "$TORRENT_FILE" ]; then
            echo " 📦 正在打包 .torrent 种子文件..."
            mktorrent -v -p -l 21 -a "${DEFAULT_TRACKER}" -o "$TORRENT_FILE" "$TARGET_PATH" > /dev/null 2>&1
        fi
    fi
    
    if [ -z "$ACTION_TYPE" ] || [ "$ACTION_TYPE" == "--only-info" ]; then
        if [ ! -f "$INFO_FILE" ]; then
            echo " 📄 正在提取 MediaInfo 数据..."
            mediainfo "$MAIN_VIDEO" > "$INFO_FILE"
        fi
    fi

    if [ -z "$ACTION_TYPE" ] || [ "$ACTION_TYPE" == "--only-img" ] || [ "$ACTION_TYPE" == "--only-gif" ]; then
        if [ ! -f "$STITCHED_IMG" ] || ([ "$ENABLE_GIF" == "true" ] && [ ! -f "$PREVIEW_WEBP" ]) || [ -n "$ACTION_TYPE" ]; then
            mkdir -p "$TMP_IMG_DIR"; LOG_FILE="$BASE_DIR/${BASE_NAME}_ffmpeg_debug.log"
            TOTAL_DUR=0; TOTAL_SIZE=0
            for vf in "${VIDEO_FILES[@]}"; do
                TOTAL_SIZE=$((TOTAL_SIZE + $(stat -c%s "$vf")))
                local fd=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$vf" | cut -d. -f1 | tr -d '\r')
                [ -n "$fd" ] && TOTAL_DUR=$((TOTAL_DUR + fd))
            done
            
            FILE_SIZE_GB=$(awk "BEGIN {printf \"%.2f\", $TOTAL_SIZE/1073741824}")
            FORMATTED_DUR=$(date -u -d @"$TOTAL_DUR" +'%H:%M:%S' 2>/dev/null)
            V_CODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$MAIN_VIDEO" | head -n1)
            V_RES=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$MAIN_VIDEO" | head -n1)
            A_CODEC=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$MAIN_VIDEO" | head -n1)
            
            local D_NAME="$TARGET_NAME"; [ "$IS_FILE" = true ] && D_NAME="${TARGET_NAME%.*}"
            
            local V_W=$(echo $V_RES | cut -d'x' -f1)
            local V_H=$(echo $V_RES | cut -d'x' -f2)
            
            local IS_VR=0
            local COLS=5
            local ROWS=3
            
            if echo "$D_NAME" | grep -qiE "vr|sbs|lr"; then 
                IS_VR=1
                V_W=$((V_W / 2))
                COLS=4
            fi

            local SHOTS=$(( COLS * ROWS ))
            local TOTAL_W=3840
            local TILE_W=$(( TOTAL_W / COLS ))
            local TILE_H=$(( V_H * TILE_W / V_W ))
            TILE_H=$(( TILE_H / 2 * 2 )) 

            local HEADER_H=100 
            local VOL_INFO=""; [ ${#VIDEO_FILES[@]} -gt 1 ] && VOL_INFO=" [共${#VIDEO_FILES[@]}卷]"
            
            echo "文件名: $D_NAME$VOL_INFO   |   体积: $FILE_SIZE_GB GiB   |   时长: $FORMATTED_DUR   |   影像: $V_CODEC ($V_RES)   |   音频: $A_CODEC" > "$TMP_IMG_DIR/h_all.txt"
            
            HEADER_IMG="$TMP_IMG_DIR/header.jpg"
            ffmpeg -nostdin -y -f lavfi -i color=c=white:s=${TOTAL_W}x${HEADER_H} -frames:v 1 -vf "drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/h_all.txt':fontcolor=black:fontsize=40:x=50:y=(h-text_h)/2" "$HEADER_IMG" >> "$LOG_FILE" 2>&1

            # =====================================================================
            # 🎬 动态 WebP 引擎 (内存盘全速运转)
            # =====================================================================
            if [ "$ENABLE_GIF" == "true" ] && ([ -z "$ACTION_TYPE" ] || [ "$ACTION_TYPE" == "--only-gif" ]); then
                if [ ! -f "$PREVIEW_WEBP" ] || [ "$ACTION_TYPE" == "--only-gif" ]; then
                    echo " 🎬 [WebP引擎] 正在受控并发提取动图 (启用物理 2 秒大跨度延时)..."
                    
                    local INTERVAL=$(( TOTAL_DUR / (SHOTS + 1) ))
                    [ "$INTERVAL" -le 0 ] && INTERVAL=1
                    
                    mkdir -p "$TMP_IMG_DIR/slices"

                    local current_jobs_gif=0
                    for (( i=1; i<=SHOTS; i++ )); do
                        local ST=$(( INTERVAL * i ))
                        local ACCUMULATED=0; local CUR_FILE=""; local REL_TIME=0; local PART_NUM=1
                        for vf in "${VIDEO_FILES[@]}"; do
                            local fd=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$vf" | cut -d. -f1 | tr -d '\r')
                            [ -z "$fd" ] && fd=0; if (( ST < ACCUMULATED + fd )); then CUR_FILE="$vf"; REL_TIME=$(( ST - ACCUMULATED )); break; fi
                            ACCUMULATED=$(( ACCUMULATED + fd )); PART_NUM=$(( PART_NUM + 1 ))
                        done
                        [ -z "$CUR_FILE" ] && CUR_FILE="${VIDEO_FILES[-1]}" && REL_TIME=$((fd > 5 ? fd - 5 : 0))

                        local TIME_STR=$(printf "%02d:%02d:%02d" $((REL_TIME / 3600)) $(( (REL_TIME % 3600) / 60 )) $((REL_TIME % 60)))
                        echo "[P${PART_NUM}] ${TIME_STR}" > "$TMP_IMG_DIR/t_gif_$i.txt"

                        (
                            # 🚀 优化 3：缩放引入 flags=bilinear 降低计算量
                            local CROP_SCALE_FILTER="scale=${TILE_W}:${TILE_H}:flags=bilinear,setsar=1"
                            if [ "$IS_VR" -eq 1 ]; then CROP_SCALE_FILTER="crop=iw/2:ih:0:0,scale=${TILE_W}:${TILE_H}:flags=bilinear,setsar=1"; fi
                            
                            local SLICE_FILE="$TMP_IMG_DIR/slices/s_${i}.mp4"
                            
                            # 🚀 优化 2：强制剥离音频字幕 -map 0:v:0 -an -sn，专心搞视频！
                            ffmpeg -nostdin -y -threads 1 -ss "$REL_TIME" -i "$CUR_FILE" -map 0:v:0 -an -sn -vf "${CROP_SCALE_FILTER},fps=2,drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/t_gif_$i.txt':fontcolor=white:fontsize=36:x=12:y=h-th-12:box=1:boxcolor=black@0.6:boxborderw=4" -c:v libx264 -preset ultrafast -crf 24 -frames:v 4 "$SLICE_FILE" >> "$LOG_FILE" 2>&1
                        ) &
                        
                        current_jobs_gif=$((current_jobs_gif + 1))
                        if (( current_jobs_gif >= 3 )); then wait; current_jobs_gif=0; fi
                    done
                    wait

                    echo "    -> 切片组装：动态合成全矩阵..."
                    
                    local FFMPEG_CMD=("ffmpeg" "-nostdin" "-y" "-threads" "0" "-hide_banner" "-loglevel" "warning" "-i" "$HEADER_IMG")
                    for (( i=1; i<=SHOTS; i++ )); do FFMPEG_CMD+=("-i" "$TMP_IMG_DIR/slices/s_${i}.mp4"); done
                    
                    local FILTER_COMPLEX=""
                    local row_idx=1
                    for (( r=0; r<ROWS; r++ )); do
                        local row_inputs=""
                        for (( c=1; c<=COLS; c++ )); do
                            local idx=$(( r * COLS + c ))
                            row_inputs+="[${idx}:v]"
                        done
                        FILTER_COMPLEX+="${row_inputs}hstack=inputs=${COLS}:shortest=1[r${row_idx}];"
                        row_idx=$((row_idx + 1))
                    done
                    
                    local vstack_inputs=""
                    for (( r=1; r<=ROWS; r++ )); do vstack_inputs+="[r${r}]"; done
                    FILTER_COMPLEX+="${vstack_inputs}vstack=inputs=${ROWS}:shortest=1[matrix];[0:v][matrix]vstack=inputs=2[out]"
                    
                    # 🚀 添加 WebP 静态图片预设优化 (-preset picture)
                    FFMPEG_CMD+=("-filter_complex" "$FILTER_COMPLEX" "-map" "[out]" "-c:v" "libwebp" "-preset" "picture" "-loop" "0" "-q:v" "75" "-compression_level" "0" "-row-mt" "1" "$PREVIEW_WEBP")

                    "${FFMPEG_CMD[@]}" >> "$LOG_FILE" 2>&1
                fi
            fi

            # =====================================================================
            # 🖼️ 静态 4K WebP 引擎 (极致优化解码版)
            # =====================================================================
            if [ -z "$ACTION_TYPE" ] || [ "$ACTION_TYPE" == "--only-img" ]; then
                if [ ! -f "$STITCHED_IMG" ] || [ "$ACTION_TYPE" == "--only-img" ]; then
                    echo " 🖼️ 正在生成自适应 4K WebP 静态海报 (${COLS}x${ROWS}阵列)..."
                    
                    local current_jobs=0
                    for (( i=1; i<=SHOTS; i++ )); do
                        local ST=$(( TOTAL_DUR * (5 + (i-1) * 90 / (SHOTS-1)) / 100 ))
                        local ACCUMULATED=0; local CUR_FILE=""; local REL_TIME=0; local PART_NUM=1
                        for vf in "${VIDEO_FILES[@]}"; do
                            local fd=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$vf" | cut -d. -f1 | tr -d '\r')
                            [ -z "$fd" ] && fd=0; if (( ST < ACCUMULATED + fd )); then CUR_FILE="$vf"; REL_TIME=$(( ST - ACCUMULATED )); break; fi
                            ACCUMULATED=$(( ACCUMULATED + fd )); PART_NUM=$(( PART_NUM + 1 ))
                        done
                        [ -z "$CUR_FILE" ] && CUR_FILE="${VIDEO_FILES[-1]}" && REL_TIME=$((fd > 5 ? fd - 5 : 0))

                        local TIME_STR=$(printf "%02d:%02d:%02d" $((REL_TIME / 3600)) $(( (REL_TIME % 3600) / 60 )) $((REL_TIME % 60)))
                        echo "[P${PART_NUM}] ${TIME_STR}" > "$TMP_IMG_DIR/t$i.txt"

                        (
                            # 🚀 优化 2：强制剥离音频字幕 -map 0:v:0 -an -sn，极大降低单帧提取时间！
                            if [ "$IS_VR" -eq 1 ]; then
                                ffmpeg -nostdin -y -threads 1 -ss "$REL_TIME" -i "$CUR_FILE" -map 0:v:0 -an -sn -vframes 1 -q:v 2 -vf "crop=iw/2:ih:0:0,scale=${TILE_W}:${TILE_H}:flags=bilinear,drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/t$i.txt':fontcolor=white:fontsize=36:x=20:y=h-th-20:box=1:boxcolor=black@0.6" "$TMP_IMG_DIR/s_$i.jpg" >> "$LOG_FILE" 2>&1
                            else
                                ffmpeg -nostdin -y -threads 1 -ss "$REL_TIME" -i "$CUR_FILE" -map 0:v:0 -an -sn -vframes 1 -q:v 2 -vf "scale=${TILE_W}:${TILE_H}:flags=bilinear,drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/t$i.txt':fontcolor=white:fontsize=36:x=20:y=h-th-20:box=1:boxcolor=black@0.6" "$TMP_IMG_DIR/s_$i.jpg" >> "$LOG_FILE" 2>&1
                            fi
                        ) &
                        
                        current_jobs=$((current_jobs + 1)); if (( current_jobs >= 3 )); then wait; current_jobs=0; fi
                    done; wait

                    for (( i=1; i<=SHOTS; i++ )); do
                        if [ ! -f "$TMP_IMG_DIR/s_$i.jpg" ]; then
                            ffmpeg -nostdin -f lavfi -i color=c=black:s=${TILE_W}x${TILE_H} -vframes 1 -y "$TMP_IMG_DIR/s_$i.jpg" >/dev/null 2>&1
                        fi
                    done

                    local FFMPEG_CMD_IMG=("ffmpeg" "-nostdin" "-y" "-threads" "0" "-i" "$HEADER_IMG")
                    for (( i=1; i<=SHOTS; i++ )); do FFMPEG_CMD_IMG+=("-i" "$TMP_IMG_DIR/s_$i.jpg"); done
                    
                    local FILTER_COMPLEX_IMG=""
                    local row_idx=1
                    for (( r=0; r<ROWS; r++ )); do
                        local row_inputs=""
                        for (( c=1; c<=COLS; c++ )); do
                            local idx=$(( r * COLS + c ))
                            row_inputs+="[${idx}:v]"
                        done
                        FILTER_COMPLEX_IMG+="${row_inputs}hstack=inputs=${COLS}[r${row_idx}];"
                        row_idx=$((row_idx + 1))
                    done
                    
                    local vstack_inputs=""
                    for (( r=1; r<=ROWS; r++ )); do vstack_inputs+="[r${r}]"; done
                    FILTER_COMPLEX_IMG+="${vstack_inputs}vstack=inputs=${ROWS}[matrix];[0:v][matrix]vstack=inputs=2"

                    # 🚀 优化 3：使用甜点画质 -q:v 85 (替代极度拖慢速度的90) 并加入 -preset picture
                    FFMPEG_CMD_IMG+=("-filter_complex" "$FILTER_COMPLEX_IMG" "-c:v" "libwebp" "-preset" "picture" "-q:v" "85" "-compression_level" "0" "-row-mt" "1" "$STITCHED_IMG")
                    
                    "${FFMPEG_CMD_IMG[@]}" >> "$LOG_FILE" 2>&1
                fi
            fi
            echo " ✅ 指令微操已执行完毕！" && rm -f "$LOG_FILE"
            rm -rf "$TMP_IMG_DIR"
        fi
    fi
}

if [ "$1" == "--folder" ] && [ -n "$2" ]; then process_target "$2" "$3"; exit 0
elif [ "$1" == "--auto" ]; then for item in "$BASE_DIR"/*; do [ -e "$item" ] && [[ "$(basename "$item")" != .* ]] && process_target "$(basename "$item")" ""; done; exit 0; fi

while true; do
    clear
    echo -e "\033[1;36m======================================\033[0m"
    echo -e "\033[1;33m PT 制种引擎 V9.8.14 (内存盘榨干极限版) \033[0m"
    echo -e "\033[1;36m======================================\033[0m"
    echo -e " \033[1;32m[1]\033[0m 自动模式 | \033[1;32m[2]\033[0m 手动模式"
    echo -e " \033[1;35m[3]\033[0m 云端同步 | \033[1;34m[5]\033[0m 动态 WebP 开关 (当前: \033[1;33m$ENABLE_GIF\033[0m)"
    echo -e " \033[1;31m[4]\033[0m 退出程序"
    read -p " 请选择: " MODE
    case $MODE in
        1) for item in "$BASE_DIR"/*; do [ -e "$item" ] && [[ "$(basename "$item")" != .* ]] && process_target "$(basename "$item")" ""; done; break ;;
        2) read -p " 输入名称: " NAME; process_target "$NAME" ""; break ;;
        3) curl -Ls https://raw.githubusercontent.com/taizi8888/argOSBX/shdetai/pt-webui/pt_make.sh | tr -d '\r' > "$(readlink -f "$0")" && exec "$(readlink -f "$0")" ;;
        5) [ "$ENABLE_GIF" = "true" ] && ENABLE_GIF="false" || ENABLE_GIF="true"; echo "ENABLE_GIF=\"$ENABLE_GIF\"" > "$CONFIG_FILE" ;;
        4|"") exit 0 ;;
    esac
done
