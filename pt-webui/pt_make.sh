#!/bin/bash
# 描述: PT 制种引擎 V9.8.7 (无极自适应版: 5x3 黄金阵列 + 0黑边完美适配)

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
TMP_ROOT="/tmp/pt_make_$(date +%s)"
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
            echo "File: $D_NAME [共 ${#VIDEO_FILES[@]} 个分卷]" > "$TMP_IMG_DIR/h1.txt"
            echo "Size: $TOTAL_SIZE bytes ($FILE_SIZE_GB GiB), duration: $FORMATTED_DUR" > "$TMP_IMG_DIR/h2.txt"
            echo "Video: $V_CODEC, $V_RES" > "$TMP_IMG_DIR/h3.txt"
            echo "Audio: $A_CODEC" > "$TMP_IMG_DIR/h4.txt"
            
            # =====================================================================
            # 🤖 核心逻辑：读取视频真实比例，全量自适应计算宽高，彻底消灭黑边！
            # =====================================================================
            local V_W=$(echo $V_RES | cut -d'x' -f1)
            local V_H=$(echo $V_RES | cut -d'x' -f2)
            local IS_VR=0
            if echo "$D_NAME" | grep -qiE "vr|sbs|lr"; then 
                IS_VR=1
                V_W=$((V_W / 2)) # VR 视频取单眼宽度计算比例
            fi

            # 设定单格宽度为 768px (横向5格 = 3840px)
            local TILE_W=768
            # 智能等比例推算单格高度
            local TILE_H=$(( V_H * TILE_W / V_W ))
            # 确保高度为偶数（FFmpeg 的强迫症要求）
            TILE_H=$(( TILE_H / 2 * 2 ))
            
            local TOTAL_W=$(( TILE_W * 5 ))
            local HEADER_H=320 # 适配头图高度
            
            # 根据计算出的完美总宽度，动态生成 Header (绝不差1像素)
            HEADER_IMG="$TMP_IMG_DIR/header.jpg"
            ffmpeg -nostdin -y -f lavfi -i color=c=white:s=${TOTAL_W}x${HEADER_H} -frames:v 1 -vf "drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/h1.txt':fontcolor=black:fontsize=50:x=40:y=30,drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/h2.txt':fontcolor=black:fontsize=50:x=40:y=100,drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/h3.txt':fontcolor=black:fontsize=50:x=40:y=170,drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/h4.txt':fontcolor=black:fontsize=50:x=40:y=240" "$HEADER_IMG" >> "$LOG_FILE" 2>&1

            # 统一采用 5x3 阵列 (15格)
            local SHOTS=15

            # =====================================================================
            # 🎬 动态 WebP 引擎 (自适应 5x3 无黑边)
            # =====================================================================
            if [ "$ENABLE_GIF" == "true" ] && ([ -z "$ACTION_TYPE" ] || [ "$ACTION_TYPE" == "--only-gif" ]); then
                if [ ! -f "$PREVIEW_WEBP" ] || [ "$ACTION_TYPE" == "--only-gif" ]; then
                    echo " 🎬 [WebP引擎] 正在受控并发提取动图帧 (自适应无黑边 5x3矩阵)..."
                    
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
                            # 自适应缩放，彻底抛弃死板的 crop
                            local CROP_SCALE_FILTER="scale=${TILE_W}:${TILE_H},setsar=1"
                            if [ "$IS_VR" -eq 1 ]; then CROP_SCALE_FILTER="crop=iw/2:ih:0:0,scale=${TILE_W}:${TILE_H},setsar=1"; fi
                            
                            local SLICE_FILE="$TMP_IMG_DIR/slices/s_${i}.mp4"
                            
                            ffmpeg -nostdin -y -threads 1 -ss "$REL_TIME" -i "$CUR_FILE" -vf "${CROP_SCALE_FILTER},fps=6,drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/t_gif_$i.txt':fontcolor=white:fontsize=36:x=12:y=h-th-12:box=1:boxcolor=black@0.6:boxborderw=4" -c:v libx264 -preset ultrafast -crf 24 -an -frames:v 6 "$SLICE_FILE" >> "$LOG_FILE" 2>&1
                        ) &
                        
                        current_jobs_gif=$((current_jobs_gif + 1))
                        # 动图并发池控制 (维持3核心平稳)
                        if (( current_jobs_gif >= 3 )); then wait; current_jobs_gif=0; fi
                    done
                    wait

                    echo "    -> 切片组装：执行 Level 0 极速合并..."
                    
                    local FFMPEG_CMD=("ffmpeg" "-nostdin" "-y" "-threads" "0" "-hide_banner" "-loglevel" "warning")
                    local FILTER_COMPLEX=""

                    FFMPEG_CMD+=("-i" "$HEADER_IMG")
                    for (( i=1; i<=SHOTS; i++ )); do
                        FFMPEG_CMD+=("-i" "$TMP_IMG_DIR/slices/s_${i}.mp4")
                    done
                    
                    # 组装 5 列，共 3 行
                    FILTER_COMPLEX+="[1:v][2:v][3:v][4:v][5:v]hstack=inputs=5:shortest=1[r1];"
                    FILTER_COMPLEX+="[6:v][7:v][8:v][9:v][10:v]hstack=inputs=5:shortest=1[r2];"
                    FILTER_COMPLEX+="[11:v][12:v][13:v][14:v][15:v]hstack=inputs=5:shortest=1[r3];"
                    
                    # 去除 crop 强切逻辑，让其自然垂直拼接，彻底消除黑边
                    FILTER_COMPLEX+="[r1][r2][r3]vstack=inputs=3:shortest=1[matrix];"
                    FILTER_COMPLEX+="[0:v][matrix]vstack=inputs=2[out]"
                    
                    # -compression_level 0 最速出图
                    FFMPEG_CMD+=("-filter_complex" "$FILTER_COMPLEX" "-map" "[out]" "-c:v" "libwebp" "-loop" "0" "-q:v" "75" "-compression_level" "0" "-row-mt" "1" "$PREVIEW_WEBP")

                    "${FFMPEG_CMD[@]}" >> "$LOG_FILE" 2>&1
                fi
            fi

            # =====================================================================
            # 🖼️ 静态 4K WebP 引擎 (自适应 5x3 无黑边)
            # =====================================================================
            if [ -z "$ACTION_TYPE" ] || [ "$ACTION_TYPE" == "--only-img" ]; then
                if [ ! -f "$STITCHED_IMG" ] || [ "$ACTION_TYPE" == "--only-img" ]; then
                    echo " 🖼️ 正在生成自适应 4K WebP 静态海报..."
                    
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
                            # 自适应宽高等比缩放
                            if [ "$IS_VR" -eq 1 ]; then
                                ffmpeg -nostdin -y -threads 1 -ss "$REL_TIME" -i "$CUR_FILE" -vframes 1 -q:v 2 -vf "crop=iw/2:ih:0:0,scale=${TILE_W}:${TILE_H},drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/t$i.txt':fontcolor=white:fontsize=36:x=20:y=h-th-20:box=1:boxcolor=black@0.6" "$TMP_IMG_DIR/s_$i.jpg" >> "$LOG_FILE" 2>&1
                            else
                                ffmpeg -nostdin -y -threads 1 -ss "$REL_TIME" -i "$CUR_FILE" -vframes 1 -q:v 2 -vf "scale=${TILE_W}:${TILE_H},drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/t$i.txt':fontcolor=white:fontsize=36:x=20:y=h-th-20:box=1:boxcolor=black@0.6" "$TMP_IMG_DIR/s_$i.jpg" >> "$LOG_FILE" 2>&1
                            fi
                        ) &
                        
                        current_jobs=$((current_jobs + 1)); if (( current_jobs >= 3 )); then wait; current_jobs=0; fi
                    done; wait

                    # 智能填补失败帧，严格匹配动态计算出的 TILE_W 和 TILE_H，绝不产生偏差
                    for (( i=1; i<=SHOTS; i++ )); do
                        if [ ! -f "$TMP_IMG_DIR/s_$i.jpg" ]; then
                            ffmpeg -nostdin -f lavfi -i color=c=black:s=${TILE_W}x${TILE_H} -vframes 1 -y "$TMP_IMG_DIR/s_$i.jpg" >/dev/null 2>&1
                        fi
                    done

                    # 所有模式统一采用 5x3 的 15格无损矩阵拼装
                    ffmpeg -nostdin -y -threads 0 -i "$HEADER_IMG" \
                    -i "$TMP_IMG_DIR/s_1.jpg" -i "$TMP_IMG_DIR/s_2.jpg" -i "$TMP_IMG_DIR/s_3.jpg" -i "$TMP_IMG_DIR/s_4.jpg" -i "$TMP_IMG_DIR/s_5.jpg" \
                    -i "$TMP_IMG_DIR/s_6.jpg" -i "$TMP_IMG_DIR/s_7.jpg" -i "$TMP_IMG_DIR/s_8.jpg" -i "$TMP_IMG_DIR/s_9.jpg" -i "$TMP_IMG_DIR/s_10.jpg" \
                    -i "$TMP_IMG_DIR/s_11.jpg" -i "$TMP_IMG_DIR/s_12.jpg" -i "$TMP_IMG_DIR/s_13.jpg" -i "$TMP_IMG_DIR/s_14.jpg" -i "$TMP_IMG_DIR/s_15.jpg" \
                    -filter_complex "[1:v][2:v][3:v][4:v][5:v]hstack=inputs=5[r1];[6:v][7:v][8:v][9:v][10:v]hstack=inputs=5[r2];[11:v][12:v][13:v][14:v][15:v]hstack=inputs=5[r3];[r1][r2][r3]vstack=inputs=3[matrix];[0:v][matrix]vstack=inputs=2" \
                    -c:v libwebp -q:v 90 -compression_level 0 -row-mt 1 "$STITCHED_IMG" >> "$LOG_FILE" 2>&1
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
    echo -e "\033[1;33m PT 制种引擎 V9.8.7 (无极自适应阵列版) \033[0m"
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
