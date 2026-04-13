#!/bin/bash
# 强制设置基础环境变量
export LANG=zh_CN.UTF-8

# 从环境变量读取目录，Docker 内我们统一挂载到 /downloads
BASE_DIR="${BASE_DIR:-/downloads}"
DEFAULT_TRACKER="https://rousi.pro/tracker/808263a94ed47ca690395ca957b562e4/announce"

# ================= 字体环境初始化 =================
FONT_DIR="$BASE_DIR/.config"
mkdir -p "$FONT_DIR"
FONT_FILE="$FONT_DIR/NotoSansSC-Regular.ttf"

if [ ! -f "$FONT_FILE" ]; then
    curl -Ls "https://github.com/google/fonts/raw/main/ofl/notosanssc/NotoSansSC-Regular.ttf" -o "$FONT_FILE"
fi
# =================================================

process_folder() {
    local FOLDER_NAME=$1
    local FOLDER_PATH="$BASE_DIR/$FOLDER_NAME"
    local TORRENT_FILE="$BASE_DIR/${FOLDER_NAME}.torrent"
    local INFO_FILE="$BASE_DIR/${FOLDER_NAME}_mediainfo.txt"
    local STITCHED_IMG="$BASE_DIR/${FOLDER_NAME}_Stitched_4K.jpg"
    local TMP_IMG_DIR="/tmp/pt_screens_$(date +%s)"

    # 1. 终极防御：拦截 .!qB
    if find "$FOLDER_PATH" -type f -name "*.!qB" | grep -q .; then return; fi

    # 2. 净网与去水印 (250M阈值，多格式，拦截 log)
    find "$FOLDER_PATH" -type f \( -iname "*.url" -o -iname "*.txt" -o -iname "*.nfo" -o -iname "*.log" \) -delete > /dev/null 2>&1
    find "$FOLDER_PATH" -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.wmv" -o -iname "*.ts" \) -size -250M -delete > /dev/null 2>&1
    for file in "$FOLDER_PATH"/*; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            if [[ "$filename" == *"@"* ]]; then mv "$file" "$FOLDER_PATH/${filename#*@}"; fi
        fi
    done

    # 3. 增量判断
    local NEED_MAKE_TORRENT=true
    local NEED_FFMPEG=true
    [[ -f "$TORRENT_FILE" && -f "$INFO_FILE" ]] && NEED_MAKE_TORRENT=false
    [[ -f "$STITCHED_IMG" ]] && NEED_FFMPEG=false
    if [ "$NEED_MAKE_TORRENT" = false ] && [ "$NEED_FFMPEG" = false ]; then return; fi

    # 4. 制作种子与参数
    mapfile -t VIDEO_FILES < <(find "$FOLDER_PATH" -maxdepth 1 \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.wmv" -o -iname "*.ts" \) | sort)
    NUM_FILES=${#VIDEO_FILES[@]}
    
    if [ "$NUM_FILES" -gt 0 ]; then
        MAIN_VIDEO=$(find "$FOLDER_PATH" -maxdepth 1 \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.wmv" -o -iname "*.ts" \) -printf "%s\t%p\n" | sort -nr | head -n1 | cut -f2)
        
        if [ "$NEED_MAKE_TORRENT" = true ]; then
            [ -n "$MAIN_VIDEO" ] && mediainfo "$MAIN_VIDEO" > "$INFO_FILE"
            local CURRENT_TRACKER="${CUSTOM_TRACKER:-$DEFAULT_TRACKER}"
            local PIECE_L=""
            
            if [ -n "$CUSTOM_PIECE_L" ]; then
                PIECE_L="$CUSTOM_PIECE_L"
            else
                SIZE_MB=$(du -sm "$FOLDER_PATH" | cut -f1)
                if [ "$SIZE_MB" -lt 512 ]; then PIECE_L=18
                elif [ "$SIZE_MB" -lt 1024 ]; then PIECE_L=19
                elif [ "$SIZE_MB" -lt 2048 ]; then PIECE_L=20
                elif [ "$SIZE_MB" -lt 4096 ]; then PIECE_L=21
                elif [ "$SIZE_MB" -lt 8192 ]; then PIECE_L=22
                elif [ "$SIZE_MB" -lt 16384 ]; then PIECE_L=23
                else PIECE_L=24
                fi
            fi
            mktorrent -v -p -l "$PIECE_L" -a "$CURRENT_TRACKER" -o "$TORRENT_FILE" "$FOLDER_PATH" > /dev/null 2>&1
        fi
    fi

    # 5. 截图与拼合
    if [ "$NEED_FFMPEG" = true ] && [ "$NUM_FILES" -gt 0 ]; then
        mkdir -p "$TMP_IMG_DIR"
        MAX_JOBS=4
        LOG_FILE="$BASE_DIR/${FOLDER_NAME}_ffmpeg_debug.log"
        
        FILE_NAME=$(basename "$MAIN_VIDEO")
        if [ "$NUM_FILES" -gt 1 ]; then
            FILE_NAME="$(basename "$FOLDER_PATH") [共 $NUM_FILES 个分卷]"
        fi
        
        TOTAL_SIZE=0
        TOTAL_DUR=0
        for vf in "${VIDEO_FILES[@]}"; do
            fs=$(stat -c%s "$vf")
            TOTAL_SIZE=$((TOTAL_SIZE + fs))
            fd=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$vf" | cut -d. -f1)
            [ -n "$fd" ] && TOTAL_DUR=$((TOTAL_DUR + fd))
        done
        
        FILE_SIZE_GB=$(awk "BEGIN {printf \"%.2f\", $TOTAL_SIZE/1073741824}")
        FORMATTED_DUR=$(date -u -d @"$TOTAL_DUR" +'%H:%M:%S')
        
        BITRATE=$(ffprobe -v error -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 "$MAIN_VIDEO")
        [ -z "$BITRATE" ] && BITRATE=0
        BITRATE_KBPS=$((BITRATE / 1000))
        
        V_CODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$MAIN_VIDEO" | head -n1)
        V_RES=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$MAIN_VIDEO" | head -n1)
        V_FPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$MAIN_VIDEO" | head -n1)
        [ -z "$V_FPS" ] && V_FPS="0/1"
        V_FPS_CALC=$(awk "BEGIN {printf \"%.2f\", $V_FPS}" 2>/dev/null || echo "Unknown")
        
        A_CODEC=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$MAIN_VIDEO" | head -n1)
        A_SR=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$MAIN_VIDEO" | head -n1)

        INFO_TXT="$TMP_IMG_DIR/header_info.txt"
        echo -e "File: $FILE_NAME\nSize: $TOTAL_SIZE bytes ($FILE_SIZE_GB GiB), duration: $FORMATTED_DUR, bitrate: $BITRATE_KBPS kb/s\nVideo: $V_CODEC, $V_RES, $V_FPS_CALC fps\nAudio: $A_CODEC, $A_SR Hz" > "$INFO_TXT"

        HEADER_IMG="$TMP_IMG_DIR/header.jpg"
        ffmpeg -y -f lavfi -i color=c=white:s=3840x350 -frames:v 1 \
        -vf "drawtext=fontfile='$FONT_FILE':textfile='$INFO_TXT':fontcolor=black:fontsize=48:x=30:y=30:line_spacing=20" \
        "$HEADER_IMG" >> "$LOG_FILE" 2>&1

        # ---------------- 智能嗅探逻辑 ----------------
        LAYOUT="${CUSTOM_LAYOUT:-auto}"
        if [ "$LAYOUT" == "auto" ]; then
            VID_WIDTH=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 "$MAIN_VIDEO" | head -n1)
            [ -z "$VID_WIDTH" ] && VID_WIDTH=1920
            if [ "$VID_WIDTH" -ge 5000 ]; then LAYOUT="vr"; else LAYOUT="standard"; fi
        fi

        # ================= 截图策略 =================
        if [ "$LAYOUT" == "vr" ]; then
            echo "提取 8 张 VR 截图..." >> "$LOG_FILE"
            for i in {0..7}; do
                FILE_IDX=$(( i % NUM_FILES ))
                CUR_FILE="${VIDEO_FILES[$FILE_IDX]}"
                
                CUR_DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$CUR_FILE" | cut -d. -f1)
                [ -z "$CUR_DUR" ] && CUR_DUR=300
                TIMESTAMP=$(( CUR_DUR * (5 + i * 12) / 100 ))
                
                TIME_TXT="$TMP_IMG_DIR/time_$i.txt"
                printf "%02d:%02d:%02d" $((TIMESTAMP / 3600)) $(( (TIMESTAMP % 3600) / 60 )) $((TIMESTAMP % 60)) > "$TIME_TXT"
                
                ( ffmpeg -y -ss "$TIMESTAMP" -i "$CUR_FILE" -frames:v 1 -q:v 2 \
                  -vf "scale=3840:-2,drawtext=fontfile='$FONT_FILE':textfile='$TIME_TXT':fontcolor=white:fontsize=64:x=40:y=h-th-40:box=1:boxcolor=black@0.6:boxborderw=15" \
                  "$TMP_IMG_DIR/shot_$i.jpg" >> "$LOG_FILE" 2>&1 ) &
                if [[ $(($((i + 1)) % $MAX_JOBS)) -eq 0 ]]; then wait; fi
            done
            wait

            MISSING=0
            for i in {0..7}; do [ ! -f "$TMP_IMG_DIR/shot_$i.jpg" ] && MISSING=1; done
            if [ "$MISSING" -eq 0 ]; then
                ffmpeg -y \
                -i "$HEADER_IMG" \
                -i "$TMP_IMG_DIR/shot_0.jpg" -i "$TMP_IMG_DIR/shot_1.jpg" -i "$TMP_IMG_DIR/shot_2.jpg" -i "$TMP_IMG_DIR/shot_3.jpg" \
                -i "$TMP_IMG_DIR/shot_4.jpg" -i "$TMP_IMG_DIR/shot_5.jpg" -i "$TMP_IMG_DIR/shot_6.jpg" -i "$TMP_IMG_DIR/shot_7.jpg" \
                -filter_complex "vstack=inputs=9" -q:v 3 "$STITCHED_IMG" >> "$LOG_FILE" 2>&1
