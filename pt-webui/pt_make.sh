#!/bin/bash
# 路径: /root/pt_make.sh
# 描述: PT 制种引擎 V6.3 (shdetai 海外高速版)

export LANG=zh_CN.UTF-8

# ==========================================
# 0. 固化与自愈逻辑
# ==========================================
if [[ "$1" != "--folder" ]] && [[ "$1" != "--auto" ]]; then
    if [ ! -f "/usr/local/bin/p" ] || [ "$(readlink -f "$0")" != "/usr/local/bin/p" ]; then
        if [ -f "/root/pt_make.sh" ]; then
            echo " ✨ 正在固化全局指令 'p'..."
            sed -i '/alias p=/d' "$HOME/.bashrc"
            cp /root/pt_make.sh /usr/local/bin/p
            chmod +x /usr/local/bin/p
            exec /usr/local/bin/p
        fi
    fi
fi

BASE_DIR="${BASE_DIR:-/home/docker/qbittorrent/downloads}"
DEFAULT_TRACKER="https://rousi.pro/tracker/808263a94ed47ca690395ca957b562e4/announce"
TMP_ROOT="/tmp/pt_make_$(date +%s)"
FONT_DIR="$BASE_DIR/.config"
FONT_FILE="$FONT_DIR/LXGWWenKaiLite-Regular.ttf"

trap 'rm -rf "$TMP_ROOT"; exit' INT TERM EXIT

check_env() {
    if [ ! -s "$FONT_FILE" ]; then
        echo " ⏳ 下载字体 (海外直连)..."
        mkdir -p "$FONT_DIR"
        curl --connect-timeout 10 -m 120 -L "https://github.com/lxgw/LxgwWenKai-Lite/releases/download/v1.330/LXGWWenKaiLite-Regular.ttf" -o "$FONT_FILE"
    fi
}
check_env

process_folder() {
    local FOLDER_NAME=$1
    local FOLDER_PATH="$BASE_DIR/$FOLDER_NAME"
    local TORRENT_FILE="$BASE_DIR/${FOLDER_NAME}.torrent"
    local INFO_FILE="$BASE_DIR/${FOLDER_NAME}_mediainfo.txt"
    local STITCHED_IMG="$BASE_DIR/${FOLDER_NAME}_Stitched_4K.jpg"
    local TMP_IMG_DIR="$TMP_ROOT/$FOLDER_NAME"

    if [[ ! -d "$FOLDER_PATH" ]]; then return; fi
    if find "$FOLDER_PATH" -type f -name "*.!qB" | grep -q .; then return; fi

    mapfile -t VIDEO_FILES < <(find "$FOLDER_PATH" -maxdepth 1 \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.wmv" -o -iname "*.ts" \) | sort)
    NUM_FILES=${#VIDEO_FILES[@]}
    [ "$NUM_FILES" -eq 0 ] && return
    
    MAIN_VIDEO=$(find "$FOLDER_PATH" -maxdepth 1 \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.wmv" -o -iname "*.ts" \) -printf "%s\t%p\n" | sort -nr | head -n1 | cut -f2)

    echo " ⏳ 制作种子与预览图: $FOLDER_NAME"
    mediainfo "$MAIN_VIDEO" > "$INFO_FILE"
    mktorrent -v -p -l 22 -a "${CUSTOM_TRACKER:-$DEFAULT_TRACKER}" -o "$TORRENT_FILE" "$FOLDER_PATH" > /dev/null 2>&1

    mkdir -p "$TMP_IMG_DIR"
    TOTAL_DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$MAIN_VIDEO" | cut -d. -f1)

    extract_screenshots() {
        local TOTAL_SHOTS=$1; local LAYOUT=$2; local MAX_CONCURRENT=3; local current_jobs=0
        for (( i=0; i<$TOTAL_SHOTS; i++ )); do
            local REL_TIME=$(( TOTAL_DUR * (5 + i * 90 / (TOTAL_SHOTS-1)) / 100 ))
            (
                if [ "$LAYOUT" == "vr" ]; then
                    ffmpeg -nostdin -y -threads 1 -ss "$REL_TIME" -i "$MAIN_VIDEO" -frames:v 1 -q:v 2 -vf "scale=2560:-2" "$TMP_IMG_DIR/shot_$i.jpg" > /dev/null 2>&1
                else
                    ffmpeg -nostdin -y -threads 1 -ss "$REL_TIME" -i "$MAIN_VIDEO" -frames:v 1 -q:v 2 -vf "scale=1280:-2" "$TMP_IMG_DIR/shot_$i.jpg" > /dev/null 2>&1
                fi
            ) &
            current_jobs=$((current_jobs + 1))
            if (( current_jobs >= MAX_CONCURRENT )); then wait; current_jobs=0; fi
        done
        wait
    }

    if [ "${CUSTOM_LAYOUT:-auto}" == "vr" ]; then
        extract_screenshots 8 "vr"
        ffmpeg -nostdin -y -i "$TMP_IMG_DIR/shot_%d.jpg" -filter_complex "vstack=inputs=8" -q:v 3 "$STITCHED_IMG" > /dev/null 2>&1
    else
        extract_screenshots 16 "standard"
        ffmpeg -nostdin -y -i "$TMP_IMG_DIR/shot_0.jpg" -i "$TMP_IMG_DIR/shot_1.jpg" -i "$TMP_IMG_DIR/shot_2.jpg" -i "$TMP_IMG_DIR/shot_3.jpg" -i "$TMP_IMG_DIR/shot_4.jpg" -i "$TMP_IMG_DIR/shot_5.jpg" -i "$TMP_IMG_DIR/shot_6.jpg" -i "$TMP_IMG_DIR/shot_7.jpg" -i "$TMP_IMG_DIR/shot_8.jpg" -i "$TMP_IMG_DIR/shot_9.jpg" -i "$TMP_IMG_DIR/shot_10.jpg" -i "$TMP_IMG_DIR/shot_11.jpg" -i "$TMP_IMG_DIR/shot_12.jpg" -i "$TMP_IMG_DIR/shot_13.jpg" -i "$TMP_IMG_DIR/shot_14.jpg" -i "$TMP_IMG_DIR/shot_15.jpg" -filter_complex "[0:v][1:v]hstack=inputs=2[r0];[2:v][3:v]hstack=inputs=2[r1];[4:v][5:v]hstack=inputs=2[r2];[6:v][7:v]hstack=inputs=2[r3];[8:v][9:v]hstack=inputs=2[r4];[10:v][11:v]hstack=inputs=2[r5];[12:v][13:v]hstack=inputs=2[r6];[14:v][15:v]hstack=inputs=2[r7];[r0][r1][r2][r3][r4][r5][r6][r7]vstack=inputs=8" -q:v 3 "$STITCHED_IMG" > /dev/null 2>&1
    fi
    rm -rf "$TMP_IMG_DIR"
}

if [ "$1" == "--folder" ]; then process_folder "$2"; exit 0; fi

clear
echo "======================================"
echo "      ArgOSBX Worker Engine V6.3      "
echo "======================================"
echo " [1] 全盘自动化扫描"
echo " [2] 指定文件夹手动制种"
echo " [3] 云端同步 (shdetai)"
echo " [4] 退出"
read -p " 请选择: " MODE
case $MODE in
    1) for d in "$BASE_DIR"/*; do [ -d "$d" ] && process_folder "$(basename "$d")"; done ;;
    2) read -p " 文件夹名: " NAME; process_folder "$NAME" ;;
    3) echo " ⏳ 同步中..."; curl -Ls --connect-timeout 10 -m 120 https://raw.githubusercontent.com/taizi8888/argOSBX/shdetai/pt-webui/pt_make.sh | tr -d '\r' > /root/pt_make.sh && chmod +x /root/pt_make.sh && exec /root/pt_make.sh ;;
    *) exit 0 ;;
esac
