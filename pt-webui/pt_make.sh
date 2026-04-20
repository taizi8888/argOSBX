#!/bin/bash
# 路径: /root/pt_make.sh
# 描述: PT 制种引擎 V4.8 (双擎路径自适应 + 满血自愈版)

export LANG=zh_CN.UTF-8

# ==========================================
# 0. 固化与自愈逻辑 (仅限物理机终端交互模式)
# ==========================================
if [[ "$1" != "--folder" ]] && [[ "$1" != "--auto" ]]; then
    if [ ! -f "/usr/local/bin/p" ] || [ "$(readlink -f "$0")" != "/usr/local/bin/p" ]; then
        if [ -f "/root/pt_make.sh" ]; then
            echo " ✨ 正在将脚本固化为系统全局指令 'p'..."
            sed -i '/alias p=/d' "$HOME/.bashrc"
            cp /root/pt_make.sh /usr/local/bin/p
            chmod +x /usr/local/bin/p
            exec /usr/local/bin/p
        fi
    fi
fi

# --- 核心配置 (自适应 Docker 与物理机路径) ---
if [ -z "$BASE_DIR" ]; then
    if [ -d "/downloads" ]; then
        BASE_DIR="/downloads"
    else
        BASE_DIR="/home/docker/qbittorrent/downloads"
    fi
fi

DEFAULT_TRACKER="https://rousi.pro/tracker/808263a94ed47ca690395ca957b562e4/announce"
TMP_ROOT="/tmp/pt_make_$(date +%s)"
FONT_DIR="$BASE_DIR/.config"
FONT_FILE="$FONT_DIR/LXGWWenKaiLite-Regular.ttf"

trap 'rm -rf "$TMP_ROOT"; exit' INT TERM EXIT

# ==========================================
# 1. 环境依赖自检 (启用防死锁机制)
# ==========================================
check_env() {
    if [ ! -s "$FONT_FILE" ]; then
        echo " ⏳ 正在拉取海报渲染专用中文字体 (启用超时保护)..."
        mkdir -p "$FONT_DIR"
        curl --connect-timeout 10 -m 120 -L "https://mirror.ghproxy.com/https://github.com/lxgw/LxgwWenKai-Lite/releases/download/v1.330/LXGWWenKaiLite-Regular.ttf" -o "$FONT_FILE"
        if [ ! -s "$FONT_FILE" ]; then
            echo " ❌ 字体下载失败！"
            rm -f "$FONT_FILE"
        fi
    fi
}
check_env

# ==========================================
# 2. 核心处理逻辑
# ==========================================
process_folder() {
    local FOLDER_NAME=$1
    local FOLDER_PATH="$BASE_DIR/$FOLDER_NAME"
    local TORRENT_FILE="$BASE_DIR/${FOLDER_NAME}.torrent"
    local INFO_FILE="$BASE_DIR/${FOLDER_NAME}_mediainfo.txt"
    local STITCHED_IMG="$BASE_DIR/${FOLDER_NAME}_Stitched_4K.jpg"
    local TMP_IMG_DIR="$TMP_ROOT/$FOLDER_NAME"

    if [[ ! -d "$FOLDER_PATH" ]]; then
        echo " ❌ 错误：找不到目标目录 => $FOLDER_PATH"
        return
    fi

    echo "------------------------------------------------"
    echo "📦 正在处理目录: $FOLDER_NAME"

    if find "$FOLDER_PATH" -type f -name "*.!qB" | grep -q .; then
        echo " ⏩ 跳过：检测到下载未完成文件 (.!qB)"
        return
    fi

    find "$FOLDER_PATH" -type f \( -iname "*.url" -o -iname "*.txt" -o -iname "*.nfo" -o -iname "*.log" \) -delete > /dev/null 2>&1
    
    local ad_cleaned=false
    for vf in "$FOLDER_PATH"/*; do
        if [[ -f "$vf" ]]; then
            local ext="${vf##*.}"; ext="${ext,,}"
            if [[ "$ext" == "mp4" || "$ext" == "mkv" || "$ext" == "avi" || "$ext" == "wmv" || "$ext" == "ts" ]]; then
                local size_kb=$(du -k "$vf" | cut -f1)
                if [ "$size_kb" -lt 256000 ]; then
                    rm -f "$vf"
                    ad_cleaned=true
                    echo " 🗑️ [净网查杀] 剔除劣质/广告视频: $(basename "$vf")" >> "$BASE_DIR/${FOLDER_NAME}_ffmpeg_debug.log"
                fi
            fi
        fi
    done
    [ "$ad_cleaned" = true ] && echo " 🧹 已完成小体积广告/样片物理清理"

    for file in "$FOLDER_PATH"/*; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            [[ "$filename" == *"@"* ]] && mv "$file" "$FOLDER_PATH/${filename#*@}"
        fi
    done

    local NEED_MAKE_TORRENT=true
    local NEED_FFMPEG=true
    [[ -f "$TORRENT_FILE" && -f "$INFO_FILE" ]] && NEED_MAKE_TORRENT=false
    [[ -f "$STITCHED_IMG" ]] && NEED_FFMPEG=false
    
    if [ "$NEED_MAKE_TORRENT" = false ] && [ "$NEED_FFMPEG" = false ]; then
        echo " ✅ 种子、参数与海报均已齐全，直接跳过。"
        return
    fi

    mapfile -t VIDEO_FILES < <(find "$FOLDER_PATH" -maxdepth 1 \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.wmv" -o -iname "*.ts" \) | sort)
    NUM_FILES=${#VIDEO_FILES[@]}
    
    if [ "$NUM_FILES" -gt 0 ]; then
        MAIN_VIDEO=$(find "$FOLDER_PATH" -maxdepth 1 \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.wmv" -o -iname "*.ts" \) -printf "%s\t%p\n" | sort -nr | head -n1 | cut -f2)
    fi
    
    if [ "$NUM_FILES" -gt 0 ] && [ "$NEED_MAKE_TORRENT" = true ]; then
        echo " ⏳ 正在制作纯净版种子与 Mediainfo 报告..."
        [ -n "$MAIN_VIDEO" ] && mediainfo "$MAIN_VIDEO" > "$INFO_FILE"
        SIZE_MB=$(du -sm "$FOLDER_PATH" | cut -f1)
        
        if [ -n "$CUSTOM_PIECE_L" ]; then
            PIECE_L=$CUSTOM_PIECE_L
        else
            if [ "$SIZE_MB" -lt 512 ]; then PIECE_L=18; elif [ "$SIZE_MB" -lt 1024 ]; then PIECE_L=19; elif [ "$SIZE_MB" -lt 2048 ]; then PIECE_L=20; elif [ "$SIZE_MB" -lt 4096 ]; then PIECE_L=21; elif [ "$SIZE_MB" -lt 8192 ]; then PIECE_L=22; elif [ "$SIZE_MB" -lt 16384 ]; then PIECE_L=23; else PIECE_L=24; fi
        fi
        
        mktorrent -v -p -l "$PIECE_L" -a "${CUSTOM_TRACKER:-$DEFAULT_TRACKER}" -o "$TORRENT_FILE" "$FOLDER_PATH" > /dev/null 2>&1
        echo " ✅ 种子制作成功 (Piece: 2^$PIECE_L)"
    fi

    if [ "$NEED_FFMPEG" = true ] && [ "$NUM_FILES" -gt 0 ] && [ -n "$MAIN_VIDEO" ]; then
        echo " ⏳ 正在提取画面并渲染海报级图文预览 (真 2K 高速并发引擎)..."
        mkdir -p "$TMP_IMG_DIR"
        LOG_FILE="$BASE_DIR/${FOLDER_NAME}_ffmpeg_debug.log"
        TOTAL_SIZE=0; TOTAL_DUR=0
        
        for vf in "${VIDEO_FILES[@]}"; do
            fs=$(stat -c%s "$vf"); TOTAL_SIZE=$((TOTAL_SIZE + fs))
            fd=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$vf" | cut -d. -f1 | tr -d '\r')
            [ -n "$fd" ] && TOTAL_DUR=$((TOTAL_DUR + fd))
        done
        
        FILE_SIZE_GB=$(awk "BEGIN {printf \"%.2f\", $TOTAL_SIZE/1073741824}")
        FORMATTED_DUR=$(date -u -d @"$TOTAL_DUR" +'%H:%M:%S' 2>/dev/null || echo "Unknown")
        
        V_CODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$MAIN_VIDEO" | head -n1 | tr -d '\r')
        V_RES=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$MAIN_VIDEO" | head -n1 | tr -d '\r')
        A_CODEC=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$MAIN_VIDEO" | head -n1 | tr -d '\r')
        
        # 物理级解耦写入文件，防止非法字符炸崩引擎
        echo "File: $(basename "$FOLDER_PATH") [共 $NUM_FILES 个分卷]" | tr -d '\r' > "$TMP_IMG_DIR/header_1.txt"
        echo "Size: $TOTAL_SIZE bytes ($FILE_SIZE_GB GiB), duration: $FORMATTED_DUR" | tr -d '\r' > "$TMP_IMG_DIR/header_2.txt"
        echo "Video: $V_CODEC, $V_RES" | tr -d '\r' > "$TMP_IMG_DIR/header_3.txt"
        echo "Audio: $A_CODEC" | tr -d '\r' > "$TMP_IMG_DIR/header_4.txt"

        HEADER_IMG="$TMP_IMG_DIR/header.jpg"
        
        ffmpeg -nostdin -y -f lavfi -i color=c=white:s=2560x280 -frames:v 1 \
        -vf "drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/header_1.txt':fontcolor=black:fontsize=38:x=30:y=20,drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/header_2.txt':fontcolor=black:fontsize=38:x=30:y=85,drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/header_3.txt':fontcolor=black:fontsize=38:x=30:y=150,drawtext=fontfile='$FONT_FILE':textfile='$TMP_IMG_DIR/header_4.txt':fontcolor=black:fontsize=38:x=30:y=215" \
        "$HEADER_IMG" >> "$LOG_FILE" 2>&1
        
        # 字体缺失容错兜底
        if [ ! -f "$HEADER_IMG" ]; then ffmpeg -nostdin -f lavfi -i color=c=black:s=2560x280 -vframes 1 -y "$HEADER_IMG" >/dev/null 2>&1; fi

        extract_screenshots() {
            local TOTAL_SHOTS=$1; local LAYOUT_TYPE=$2
            local MAX_CONCURRENT=3
            local current_jobs=0

            for (( i=0; i<$TOTAL_SHOTS; i++ )); do
                local PCT=$(( 5 + i * 90 / (TOTAL_SHOTS > 1 ? TOTAL_SHOTS - 1 : 1) ))
                local TARGET_ABS_TIME=$(( TOTAL_DUR * PCT / 100 ))
                local ACCUMULATED=0; local CUR_FILE=""; local REL_TIME=0; local PART_NUM=1

                for vf in "${VIDEO_FILES[@]}"; do
                    local fd=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$vf" | cut -d. -f1 | tr -d '\r')
                    [ -z "$fd" ] && fd=0
                    if (( TARGET_ABS_TIME < ACCUMULATED + fd )); then
                        CUR_FILE="$vf"; REL_TIME=$(( TARGET_ABS_TIME - ACCUMULATED )); break
                    fi
                    ACCUMULATED=$(( ACCUMULATED + fd )); PART_NUM=$(( PART_NUM + 1 ))
                done
                [ -z "$CUR_FILE" ] && CUR_FILE="${VIDEO_FILES[-1]}" && REL_TIME=$((fd > 5 ? fd - 5 : 0))

                local TIME_STR=$(printf "%02d:%02d:%02d" $((REL_TIME / 3600)) $(( (REL_TIME % 3600) / 60 )) $((REL_TIME % 60)))
                local TIME_TXT="$TMP_IMG_DIR/time_$i.txt"
                
                echo "[P${PART_NUM}] ${TIME_STR}" | tr -d '\r' > "$TIME_TXT"

                (
                    if [ "$LAYOUT_TYPE" == "vr" ]; then
                        ffmpeg -nostdin -y -threads 1 -ss "$REL_TIME" -i "$CUR_FILE" -frames:v 1 -q:v 2 -vf "scale=2560:-2,drawtext=fontfile='$FONT_FILE':textfile='$TIME_TXT':fontcolor=white:fontsize=48:x=30:y=h-th-30:box=1:boxcolor=black@0.6:boxborderw=10" "$TMP_IMG_DIR/shot_$i.jpg" >> "$LOG_FILE" 2>&1
                    else
                        ffmpeg -nostdin -y -threads 1 -ss "$REL_TIME" -i "$CUR_FILE" -frames:v 1 -q:v 2 -vf "scale=1280:-2,drawtext=fontfile='$FONT_FILE':textfile='$TIME_TXT':fontcolor=white:fontsize=36:x=20:y=h-th-20:box=1:boxcolor=black@0.6:boxborderw=8" "$TMP_IMG_DIR/shot_$i.jpg" >> "$LOG_FILE" 2>&1
                    fi
                ) &

                current_jobs=$((current_jobs + 1))
                if (( current_jobs >= MAX_CONCURRENT )); then wait; current_jobs=0; fi
            done
            wait 

            # 残帧黑图占位补全
            for (( i=0; i<$TOTAL_SHOTS; i++ )); do
                 if [ ! -f "$TMP_IMG_DIR/shot_$i.jpg" ]; then
                     if [ "$LAYOUT_TYPE" == "vr" ]; then
                         ffmpeg -nostdin -f lavfi -i color=c=black:s=2560x1440 -vframes 1 -y "$TMP_IMG_DIR/shot_$i.jpg" >/dev/null 2>&1
                     else
                         ffmpeg -nostdin -f lavfi -i color=c=black:s=1280x720 -vframes 1 -y "$TMP_IMG_DIR/shot_$i.jpg" >/dev/null 2>&1
                     fi
                 fi
            done
        }

        VID_WIDTH=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 "$MAIN_VIDEO" | head -n1 | tr -d '\r')
        LAYOUT_PREF="${CUSTOM_LAYOUT:-auto}"
        
        if [ "$LAYOUT_PREF" == "vr" ] || ([ "$LAYOUT_PREF" == "auto" ] && [ "${VID_WIDTH:-0}" -ge 5000 ]); then
            echo " 🌐 启用单列 VR 瀑布流排版 (输出: 2K 真并发模式)..."
            extract_screenshots 8 "vr"
            ffmpeg -nostdin -y -i "$HEADER_IMG" -i "$TMP_IMG_DIR/shot_0.jpg" -i "$TMP_IMG_DIR/shot_1.jpg" -i "$TMP_IMG_DIR/shot_2.jpg" -i "$TMP_IMG_DIR/shot_3.jpg" -i "$TMP_IMG_DIR/shot_4.jpg" -i "$TMP_IMG_DIR/shot_5.jpg" -i "$TMP_IMG_DIR/shot_6.jpg" -i "$TMP_IMG_DIR/shot_7.jpg" -filter_complex "vstack=inputs=9" -q:v 3 "$STITCHED_IMG" >> "$LOG_FILE" 2>&1
        else
            echo " 🎬 启用常规比例合并 2x8 规格图文海报 (输出: 2K 真并发模式)..."
            extract_screenshots 16 "standard"
            ffmpeg -nostdin -y -i "$HEADER_IMG" -i "$TMP_IMG_DIR/shot_0.jpg" -i "$TMP_IMG_DIR/shot_1.jpg" -i "$TMP_IMG_DIR/shot_2.jpg" -i "$TMP_IMG_DIR/shot_3.jpg" -i "$TMP_IMG_DIR/shot_4.jpg" -i "$TMP_IMG_DIR/shot_5.jpg" -i "$TMP_IMG_DIR/shot_6.jpg" -i "$TMP_IMG_DIR/shot_7.jpg" -i "$TMP_IMG_DIR/shot_8.jpg" -i "$TMP_IMG_DIR/shot_9.jpg" -i "$TMP_IMG_DIR/shot_10.jpg" -i "$TMP_IMG_DIR/shot_11.jpg" -i "$TMP_IMG_DIR/shot_12.jpg" -i "$TMP_IMG_DIR/shot_13.jpg" -i "$TMP_IMG_DIR/shot_14.jpg" -i "$TMP_IMG_DIR/shot_15.jpg" -filter_complex "[1:v][2:v]hstack=inputs=2[r0];[3:v][4:v]hstack=inputs=2[r1];[5:v][6:v]hstack=inputs=2[r2];[7:v][8:v]hstack=inputs=2[r3];[9:v][10:v]hstack=inputs=2[r4];[11:v][12:v]hstack=inputs=2[r5];[13:v][14:v]hstack=inputs=2[r6];[15:v][16:v]hstack=inputs=2[r7];[r0][r1][r2][r3][r4][r5][r6][r7]vstack=inputs=8[grid];[0:v][grid]vstack=inputs=2" -q:v 3 "$STITCHED_IMG" >> "$LOG_FILE" 2>&1
        fi
        
        [ -f "$STITCHED_IMG" ] && echo " ✅ 恭喜！海报级预览大图渲染完毕" && rm -f "$LOG_FILE"
        rm -rf "$TMP_IMG_DIR"
    fi
}

# ==========================================
# FastAPI 接口拦截与静默执行入口
# ==========================================
if [ "$1" == "--folder" ] && [ -n "$2" ]; then
    process_folder "$2"
    exit 0
elif [ "$1" == "--auto" ]; then
    for dir in "$BASE_DIR"/*; do 
        [ -d "$dir" ] && [[ "$(basename "$dir")" != .* ]] && process_folder "$(basename "$dir")"
    done
    exit 0
fi

# ==========================================
# 终端手动执行菜单 (仅在 SSH 下可见)
# ==========================================
clear
echo -e "\033[1;36m======================================\033[0m"
echo -e "\033[1;33m      PT 制种引擎 V4.8 (双擎自适应版)      \033[0m"
echo -e "\033[1;36m======================================\033[0m"
echo -e " \033[1;32m[1]\033[0m 自动模式 (全盘深度扫描与制种)"
echo -e " \033[1;32m[2]\033[0m 手动模式 (输入指定文件夹名称)"
echo -e " \033[1;35m[3]\033[0m 云端同步 (强制更新本地引擎)"
echo -e " \033[1;31m[4]\033[0m 退出程序"
echo -e "\033[1;36m======================================\033[0m"
read -p " 请选择要执行的操作 [1-4]: " MODE

case $MODE in
    1) for dir in "$BASE_DIR"/*; do [ -d "$dir" ] && [[ "$(basename "$dir")" != .* ]] && process_folder "$(basename "$dir")"; done ;;
    2) read -p " 请输入具体的文件夹名: " NAME; process_folder "$NAME" ;;
    3) echo " ⏳ 同步中..."; curl -Ls --connect-timeout 10 -m 120 https://raw.githubusercontent.com/taizi8888/argOSBX/shdetai/pt-webui/pt_make.sh | tr -d '\r' > "$(readlink -f "$0")" && chmod +x "$(readlink -f "$0")" && exec "$(readlink -f "$0")" ;;
    *) exit 0 ;;
esac
