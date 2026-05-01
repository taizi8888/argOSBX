#!/bin/bash
# 描述: PT 制种引擎 V9.8.2 (动静统一 真·4K WebP 全面解禁版)

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
            
            # 🚀 统一共用真·4K Header (3840px宽)，不再区分动图和静图
            HEADER_IMG="$TMP_IMG_DIR/header.jpg"
            ffmpeg -nostdin -y -f lavfi -i color=c=white:s=3840x350 -frames:v 1 -vf "drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/h1.txt':fontcolor=black:fontsize=50:x=40:y=30,drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/h2.txt':fontcolor=black:fontsize=50:x=40:y=110,drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/h3.txt':fontcolor=black:fontsize=50:x=40:y=190,drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/h4.txt':fontcolor=black:fontsize=50:x=40:y=270" "$HEADER_IMG" >> "$LOG_FILE" 2>&1

            # =====================================================================
            # 🎬 动态 WebP 引擎 (3840px 真·4K 动图降维打击)
            # =====================================================================
            if [ "$ENABLE_GIF" == "true" ] && ([ -z "$ACTION_TYPE" ] || [ "$ACTION_TYPE" == "--only-gif" ]); then
                if [ ! -f "$PREVIEW_WEBP" ] || [ "$ACTION_TYPE" == "--only-gif" ]; then
                    echo " 🎬 [WebP引擎] 正在串行切分素材 (1280px 单图宽，拼合 3840px 真·4K 动图)..."
                    
                    local IS_VR=0
                    if echo "$D_NAME" | grep -qiE "vr|sbs|lr"; then IS_VR=1; fi

                    local SHOTS=18
                    local INTERVAL=$(( TOTAL_DUR / (SHOTS + 1) ))
                    [ "$INTERVAL" -le 0 ] && INTERVAL=1
                    
                    mkdir -p "$TMP_IMG_DIR/slices"

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

                        # 🚀 宽度设定为 1280px，完美三等分 3840px！
                        local CROP_SCALE_FILTER="scale=1280:-2,setsar=1"
                        if [ "$IS_VR" -eq 1 ]; then CROP_SCALE_FILTER="crop=iw/2:ih:0:0,scale=1280:-2,setsar=1"; fi
                        
                        local SLICE_FILE="$TMP_IMG_DIR/slices/s_${i}.mp4"
                        
                        # 水印字体放大至 45px 适配 1280 宽带
                        ffmpeg -nostdin -y -ss "$REL_TIME" -i "$CUR_FILE" -vf "${CROP_SCALE_FILTER},fps=6,drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/t_gif_$i.txt':fontcolor=white:fontsize=45:x=20:y=h-th-20:box=1:boxcolor=black@0.6:boxborderw=6" -c:v libx264 -preset ultrafast -crf 24 -an -frames:v 6 "$SLICE_FILE" >> "$LOG_FILE" 2>&1
                    done

                    echo "    -> 切片组装：进行 24-bit 4K级动图编码 (-q:v 80)..."
                    
                    local FFMPEG_CMD=("ffmpeg" "-nostdin" "-y" "-threads" "2" "-hide_banner" "-loglevel" "warning")
                    local FILTER_COMPLEX=""

                    FFMPEG_CMD+=("-i" "$HEADER_IMG")
                    for (( i=1; i<=SHOTS; i++ )); do
                        FFMPEG_CMD+=("-i" "$TMP_IMG_DIR/slices/s_${i}.mp4")
                    done
                    
                    FILTER_COMPLEX+="[1:v][2:v][3:v]hstack=inputs=3:shortest=1[r1];"
                    FILTER_COMPLEX+="[4:v][5:v][6:v]hstack=inputs=3:shortest=1[r2];"
                    FILTER_COMPLEX+="[7:v][8:v][9:v]hstack=inputs=3:shortest=1[r3];"
                    FILTER_COMPLEX+="[10:v][11:v][12:v]hstack=inputs=3:shortest=1[r4];"
                    FILTER_COMPLEX+="[13:v][14:v][15:v]hstack=inputs=3:shortest=1[r5];"
                    FILTER_COMPLEX+="[16:v][17:v][18:v]hstack=inputs=3:shortest=1[r6];"
                    
                    # 1280 x 3 = 3840，严丝合缝无需裁剪！
                    FILTER_COMPLEX+="[r1][r2][r3][r4][r5][r6]vstack=inputs=6:shortest=1[matrix];"
                    FILTER_COMPLEX+="[0:v][matrix]vstack=inputs=2[out]"
                    
                    FFMPEG_CMD+=("-filter_complex" "$FILTER_COMPLEX" "-map" "[out]" "-c:v" "libwebp" "-loop" "0" "-q:v" "80" "$PREVIEW_WEBP")

                    "${FFMPEG_CMD[@]}" >> "$LOG_FILE" 2>&1
                fi
            fi

            # =====================================================================
            # 🖼️ 静态真·4K WebP 引擎 (3840px 超宽极限画质)
            # =====================================================================
            if [ -z "$ACTION_TYPE" ] || [ "$ACTION_TYPE" == "--only-img" ]; then
                if [ ! -f "$STITCHED_IMG" ] || [ "$ACTION_TYPE" == "--only-img" ]; then
                    echo " 🖼️ 正在生成真·4K (3840px) 静态海报..."
                    VID_W=$(echo $V_RES | cut -d'x' -f1); LAYOUT="standard"; SHOTS=16; [ "${VID_W:-0}" -ge 5000 ] && LAYOUT="vr" && SHOTS=8
                    
                    local current_jobs=0
                    for (( i=0; i<$SHOTS; i++ )); do
                        local ST=$(( TOTAL_DUR * (5 + i * 90 / (SHOTS-1)) / 100 ))
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
                            if [ "$LAYOUT" == "vr" ]; then
                                ffmpeg -nostdin -y -threads 1 -ss "$REL_TIME" -i "$CUR_FILE" -vframes 1 -q:v 2 -vf "scale=3840:-2,drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/t$i.txt':fontcolor=white:fontsize=60:x=40:y=h-th-40:box=1:boxcolor=black@0.6" "$TMP_IMG_DIR/s$i.jpg" >> "$LOG_FILE" 2>&1
                            else
                                ffmpeg -nostdin -y -threads 1 -ss "$REL_TIME" -i "$CUR_FILE" -vframes 1 -q:v 2 -vf "scale=1920:-2,drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/t$i.txt':fontcolor=white:fontsize=50:x=30:y=h-th-30:box=1:boxcolor=black@0.6" "$TMP_IMG_DIR/s$i.jpg" >> "$LOG_FILE" 2>&1
                            fi
                        ) &
                        current_jobs=$((current_jobs + 1)); if (( current_jobs >= 3 )); then wait; current_jobs=0; fi
                    done; wait

                    for (( i=0; i<$SHOTS; i++ )); do
                        if [ ! -f "$TMP_IMG_DIR/s$i.jpg" ]; then
                            [ "$LAYOUT" == "vr" ] && ffmpeg -nostdin -f lavfi -i color=c=black:s=3840x2160 -vframes 1 -y "$TMP_IMG_DIR/s$i.jpg" >/dev/null 2>&1 || ffmpeg -nostdin -f lavfi -i color=c=black:s=1920x1080 -vframes 1 -y "$TMP_IMG_DIR/s$i.jpg" >/dev/null 2>&1
                        fi
                    done

                    if [ "$LAYOUT" == "vr" ]; then
                        ffmpeg -nostdin -y -i "$HEADER_IMG" -i "$TMP_IMG_DIR/s0.jpg" -i "$TMP_IMG_DIR/s1.jpg" -i "$TMP_IMG_DIR/s2.jpg" -i "$TMP_IMG_DIR/s3.jpg" -i "$TMP_IMG_DIR/s4.jpg" -i "$TMP_IMG_DIR/s5.jpg" -i "$TMP_IMG_DIR/s6.jpg" -i "$TMP_IMG_DIR/s7.jpg" -filter_complex "vstack=inputs=9" -c:v libwebp -q:v 95 "$STITCHED_IMG" >> "$LOG_FILE" 2>&1
                    else
                        ffmpeg -nostdin -y -i "$HEADER_IMG" -i "$TMP_IMG_DIR/s0.jpg" -i "$TMP_IMG_DIR/s1.jpg" -i "$TMP_IMG_DIR/s2.jpg" -i "$TMP_IMG_DIR/s3.jpg" -i "$TMP_IMG_DIR/s4.jpg" -i "$TMP_IMG_DIR/s5.jpg" -i "$TMP_IMG_DIR/s6.jpg" -i "$TMP_IMG_DIR/s7.jpg" -i "$TMP_IMG_DIR/s8.jpg" -i "$TMP_IMG_DIR/s9.jpg" -i "$TMP_IMG_DIR/s10.jpg" -i "$TMP_IMG_DIR/s11.jpg" -i "$TMP_IMG_DIR/s12.jpg" -i "$TMP_IMG_DIR/s13.jpg" -i "$TMP_IMG_DIR/s14.jpg" -i "$TMP_IMG_DIR/s15.jpg" -filter_complex "[1:v][2:v]hstack=inputs=2[r0];[3:v][4:v]hstack=inputs=2[r1];[5:v][6:v]hstack=inputs=2[r2];[7:v][8:v]hstack=inputs=2[r3];[9:v][10:v]hstack=inputs=2[r4];[11:v][12:v]hstack=inputs=2[r5];[13:v][14:v]hstack=inputs=2[r6];[15:v][16:v]hstack=inputs=2[r7];[r0][r1][r2][r3][r4][r5][r6][r7]vstack=inputs=8[g];[0:v][g]vstack=inputs=2" -c:v libwebp -q:v 95 "$STITCHED_IMG" >> "$LOG_FILE" 2>&1
                    fi
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
    echo -e "\033[1;33m PT 制种引擎 V9.8.2 (动静统一4K 解禁版) \033[0m"
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
