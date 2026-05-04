#!/bin/bash
# 描述: PT 制种引擎 V9.8.21 (神级统合版: 一次全息扫描，动静双维同出)

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
if [ -d "/dev/shm" ]; then
    SHM_AVAIL=$(df -k /dev/shm | awk 'NR==2 {print $4}')
    if [[ "$SHM_AVAIL" =~ ^[0-9]+$ ]] && [ "$SHM_AVAIL" -gt 153600 ]; then
        TMP_ROOT="/dev/shm/pt_make_$(date +%s)"
    fi
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
        # 智能判定：是否需要生成动图和静图
        local DO_GIF=false; [ "$ENABLE_GIF" == "true" ] && [ ! -f "$PREVIEW_WEBP" ] && [[ -z "$ACTION_TYPE" || "$ACTION_TYPE" == "--only-gif" ]] && DO_GIF=true
        local DO_IMG=false; [ ! -f "$STITCHED_IMG" ] && [[ -z "$ACTION_TYPE" || "$ACTION_TYPE" == "--only-img" ]] && DO_IMG=true

        if [ "$DO_GIF" == "true" ] || [ "$DO_IMG" == "true" ]; then
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
            ffmpeg -nostdin -y -f lavfi -i color=c=white:s=${TOTAL_W}x${HEADER_H} -frames:v 1 -vf "drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/h_all.txt':fontcolor=black:fontsize=40:x=50:y=(h-text_h)/2" -c:v mjpeg -q:v 2 -pix_fmt yuvj420p "$HEADER_IMG" >> "$LOG_FILE" 2>&1

            # =====================================================================
            # 🚀 降维同出提取引擎 (一次寻址，动静齐出)
            # =====================================================================
            echo " ⏳ [统合扫描引擎] 正在全核对巨兽进行一次性空间寻址提取..."
            mkdir -p "$TMP_IMG_DIR/slices"
            
            local current_jobs=0
            for (( i=1; i<=SHOTS; i++ )); do
                # 统一使用 5% 到 95% 的完美等距时间戳算法
                local ST=$(( TOTAL_DUR * (5 + (i-1) * 90 / (SHOTS-1)) / 100 ))
                local ACCUMULATED=0; local CUR_FILE=""; local REL_TIME=0; local PART_NUM=1
                for vf in "${VIDEO_FILES[@]}"; do
                    local fd=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$vf" | cut -d. -f1 | tr -d '\r')
                    [ -z "$fd" ] && fd=0; if (( ST < ACCUMULATED + fd )); then CUR_FILE="$vf"; REL_TIME=$(( ST - ACCUMULATED )); break; fi
                    ACCUMULATED=$(( ACCUMULATED + fd )); PART_NUM=$(( PART_NUM + 1 ))
                done
                [ -z "$CUR_FILE" ] && CUR_FILE="${VIDEO_FILES[-1]}" && REL_TIME=$((fd > 5 ? fd - 5 : 0))

                local TIME_STR=$(printf "%02d:%02d:%02d" $((REL_TIME / 3600)) $(( (REL_TIME % 3600) / 60 )) $((REL_TIME % 60)))
                echo "[P${PART_NUM}] ${TIME_STR}" > "$TMP_IMG_DIR/t_$i.txt"

                (
                    local CROP_SCALE_FILTER="scale=${TILE_W}:${TILE_H}:flags=fast_bilinear,setsar=1"
                    if [ "$IS_VR" -eq 1 ]; then CROP_SCALE_FILTER="crop=iw/2:ih:0:0,scale=${TILE_W}:${TILE_H}:flags=fast_bilinear,setsar=1"; fi
                    
                    if [ "$DO_GIF" == "true" ]; then
                        # 1. 软解 8K，极速输出无压缩动图 AVI 序列
                        ffmpeg -nostdin -y -skip_loop_filter all -skip_frame noref -ss "$REL_TIME" -i "$CUR_FILE" -map 0:V:0 -an -sn -vf "${CROP_SCALE_FILTER},fps=2,drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/t_$i.txt':fontcolor=white:fontsize=36:x=16:y=h-th-16:box=1:boxcolor=black@0.6:boxborderw=4" -c:v rawvideo -pix_fmt yuv420p -frames:v 4 "$TMP_IMG_DIR/slices/s_${i}.avi" >> "$LOG_FILE" 2>&1
                        
                        if [ "$DO_IMG" == "true" ]; then
                            # 2. 借鸡生蛋：从内存盘的无压缩 AVI 中瞬间抽 1 帧做静图！0软解消耗！
                            ffmpeg -nostdin -y -i "$TMP_IMG_DIR/slices/s_${i}.avi" -vframes 1 -c:v mjpeg -q:v 2 -pix_fmt yuvj420p "$TMP_IMG_DIR/s_$i.jpg" >> "$LOG_FILE" 2>&1
                        fi
                    elif [ "$DO_IMG" == "true" ]; then
                        # 只有静图时，直接软解抽取 1 帧
                        ffmpeg -nostdin -y -skip_loop_filter all -ss "$REL_TIME" -i "$CUR_FILE" -map 0:V:0 -an -sn -vframes 1 -vf "${CROP_SCALE_FILTER},drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/t_$i.txt':fontcolor=white:fontsize=36:x=16:y=h-th-16:box=1:boxcolor=black@0.6" -c:v mjpeg -q:v 2 -pix_fmt yuvj420p "$TMP_IMG_DIR/s_$i.jpg" >> "$LOG_FILE" 2>&1
                    fi
                ) &
                
                # 并发控制：保持 3 核甜点满载并行
                current_jobs=$((current_jobs + 1))
                if (( current_jobs >= 3 )); then wait; current_jobs=0; fi
            done
            wait

            # =====================================================================
            # 🎬 动图拼装与垃圾回收
            # =====================================================================
            if [ "$DO_GIF" == "true" ]; then
                echo "    -> [拼接矩阵] 正在高速组装动态预览图..."
                local FFMPEG_CMD=("ffmpeg" "-nostdin" "-y" "-threads" "0" "-hide_banner" "-loglevel" "warning" "-i" "$HEADER_IMG")
                for (( i=1; i<=SHOTS; i++ )); do FFMPEG_CMD+=("-i" "$TMP_IMG_DIR/slices/s_${i}.avi"); done
                
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
                
                FFMPEG_CMD+=("-filter_complex" "$FILTER_COMPLEX" "-map" "[out]" "-c:v" "libwebp" "-loop" "0" "-q:v" "75" "-compression_level" "0" "-row-mt" "1" "$PREVIEW_WEBP")

                "${FFMPEG_CMD[@]}" >> "$LOG_FILE" 2>&1
                
                # 🚀 极其关键的 GC 回收：动图拼完立刻销毁内存中庞大的 AVI，安全释放 60M 空间让给后续操作！
                rm -rf "$TMP_IMG_DIR/slices"
            fi

            # =====================================================================
            # 🖼️ 静图拼装
            # =====================================================================
            if [ "$DO_IMG" == "true" ]; then
                echo "    -> [拼接矩阵] 正在色彩安全合并 4K 静态海报..."
                
                # 容错：遇到缺帧缺损，用极其干净的黑屏补齐
                for (( i=1; i<=SHOTS; i++ )); do
                    if [ ! -f "$TMP_IMG_DIR/s_$i.jpg" ]; then
                        ffmpeg -nostdin -f lavfi -i color=c=black:s=${TILE_W}x${TILE_H} -vframes 1 -c:v mjpeg -q:v 2 -pix_fmt yuvj420p -y "$TMP_IMG_DIR/s_$i.jpg" >/dev/null 2>&1
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

                FFMPEG_CMD_IMG+=("-filter_complex" "$FILTER_COMPLEX_IMG" "-c:v" "libwebp" "-q:v" "85" "-compression_level" "0" "-row-mt" "1" "$STITCHED_IMG")
                
                "${FFMPEG_CMD_IMG[@]}" >> "$LOG_FILE" 2>&1
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
    echo -e "\033[1;33m PT 制种引擎 V9.8.21 (神级单遍同出版) \033[0m"
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
