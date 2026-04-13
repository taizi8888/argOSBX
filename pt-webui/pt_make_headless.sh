#!/bin/bash
# 强制设置基础环境变量
export LANG=zh_CN.UTF-8

# 从环境变量读取目录，Docker 内我们统一挂载到 /downloads
BASE_DIR="${BASE_DIR:-/downloads}"
DEFAULT_TRACKER="https://rousi.pro/tracker/808263a94ed47ca690395ca957b562e4/announce"

process_folder() {
    local FOLDER_NAME=$1
    local FOLDER_PATH="$BASE_DIR/$FOLDER_NAME"
    local TORRENT_FILE="$BASE_DIR/${FOLDER_NAME}.torrent"
    local INFO_FILE="$BASE_DIR/${FOLDER_NAME}_mediainfo.txt"
    local STITCHED_IMG="$BASE_DIR/${FOLDER_NAME}_Stitched_4K.jpg"
    local TMP_IMG_DIR="/tmp/pt_screens_$(date +%s)"

    # 1. 终极防御：拦截 .!qB
    if find "$FOLDER_PATH" -type f -name "*.!qB" | grep -q .; then return; fi

    # 2. 净网与去水印
    find "$FOLDER_PATH" -type f \( -iname "*.url" -o -iname "*.txt" -o -iname "*.nfo" \) -delete > /dev/null 2>&1
    find "$FOLDER_PATH" -type f -iname "*.mp4" -size -50M -delete > /dev/null 2>&1
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
    mapfile -t VIDEO_FILES < <(find "$FOLDER_PATH" -maxdepth 1 -iname "*.mp4" | sort)
    NUM_FILES=${#VIDEO_FILES[@]}
    
    if [ "$NEED_MAKE_TORRENT" = true ] && [ "$NUM_FILES" -gt 0 ]; then
        MAIN_VIDEO=$(find "$FOLDER_PATH" -maxdepth 1 -iname "*.mp4" -printf "%s\t%p\n" | sort -nr | head -n1 | cut -f2)
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

    # 5. 截图与拼合
    if [ "$NEED_FFMPEG" = true ] && [ "$NUM_FILES" -gt 0 ]; then
        mkdir -p "$TMP_IMG_DIR"
        MAX_JOBS=4
        LOG_FILE="$FOLDER_PATH/ffmpeg_debug.log"
        
        # 接收前端强制排版要求，如果没有，则默认为 auto
        LAYOUT="${CUSTOM_LAYOUT:-auto}"
        
        # 🤖 智能 VR 嗅探逻辑：如果前端没强行指定，系统自己判断
        if [ "$LAYOUT" == "auto" ]; then
            TEST_FILE="${VIDEO_FILES[0]}"
            # 读取视频像素宽度
            VID_WIDTH=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 "$TEST_FILE" | head -n1)
            [ -z "$VID_WIDTH" ] && VID_WIDTH=1920
            
            # 宽度大于等于 5000 像素，必定是高分辨率 VR 资源
            if [ "$VID_WIDTH" -ge 5000 ]; then
                LAYOUT="vr"
                echo "🤖 智能探测：视频宽度为 $VID_WIDTH，判定为 VR，自动切换为瀑布流模式..." > "$LOG_FILE"
            else
                LAYOUT="standard"
                echo "🤖 智能探测：视频宽度为 $VID_WIDTH，判定为标准画幅..." > "$LOG_FILE"
            fi
        fi

        # ================= 根据最终 LAYOUT 决定截图策略 =================
        if [ "$LAYOUT" == "vr" ]; then
            # 🥽 VR 瀑布流模式 (1列 x 8行)
            echo "开始提取 8 张 VR 截图..." >> "$LOG_FILE"
            for i in {0..7}; do
                FILE_IDX=$(( i % NUM_FILES ))
                CUR_FILE="${VIDEO_FILES[$FILE_IDX]}"
                DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$CUR_FILE" | cut -d. -f1)
                [ -z "$DUR" ] && DUR=300
                TIMESTAMP=$(( DUR * (5 + i * 12) / 100 ))
                
                # 宽度固定为 3840，高度自适应
                ( ffmpeg -y -ss "$TIMESTAMP" -i "$CUR_FILE" -frames:v 1 -q:v 2 \
                  -vf "scale=3840:-2" \
                  "$TMP_IMG_DIR/shot_$i.jpg" >> "$LOG_FILE" 2>&1 ) &
                if [[ $(($((i + 1)) % $MAX_JOBS)) -eq 0 ]]; then wait; fi
            done
            wait

            MISSING=0
            for i in {0..7}; do [ ! -f "$TMP_IMG_DIR/shot_$i.jpg" ] && MISSING=1; done

            if [ "$MISSING" -eq 0 ]; then
                echo "✅ 8张VR截图就绪，使用 vstack 垂直拼合..." >> "$LOG_FILE"
                ffmpeg -y \
                -i "$TMP_IMG_DIR/shot_0.jpg" -i "$TMP_IMG_DIR/shot_1.jpg" -i "$TMP_IMG_DIR/shot_2.jpg" -i "$TMP_IMG_DIR/shot_3.jpg" \
                -i "$TMP_IMG_DIR/shot_4.jpg" -i "$TMP_IMG_DIR/shot_5.jpg" -i "$TMP_IMG_DIR/shot_6.jpg" -i "$TMP_IMG_DIR/shot_7.jpg" \
                -filter_complex "vstack=inputs=8" -q:v 3 "$STITCHED_IMG" >> "$LOG_FILE" 2>&1
                [ -f "$STITCHED_IMG" ] && rm -f "$LOG_FILE"
            fi

        else
            # 🎥 标准电影模式 (16张 2列 x 8行)
            echo "开始提取 16 张标准截图..." >> "$LOG_FILE"
            for i in {0..15}; do
                FILE_IDX=$(( i % NUM_FILES ))
                CUR_FILE="${VIDEO_FILES[$FILE_IDX]}"
                DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$CUR_FILE" | cut -d. -f1)
                [ -z "$DUR" ] && DUR=300
                TIMESTAMP=$(( DUR * (5 + i * 5) / 100 ))
                
                ( ffmpeg -y -ss "$TIMESTAMP" -i "$CUR_FILE" -frames:v 1 -q:v 2 \
                  -vf "scale=1920:-2" \
                  "$TMP_IMG_DIR/shot_$i.jpg" >> "$LOG_FILE" 2>&1 ) &
                if [[ $(($((i + 1)) % $MAX_JOBS)) -eq 0 ]]; then wait; fi
            done
            wait

            MISSING=0
            for i in {0..15}; do [ ! -f "$TMP_IMG_DIR/shot_$i.jpg" ] && MISSING=1; done

            if [ "$MISSING" -eq 0 ]; then
                echo "✅ 16张截图就绪，开始拼合 4K 巨幕..." >> "$LOG_FILE"
                ffmpeg -y \
                -i "$TMP_IMG_DIR/shot_0.jpg" -i "$TMP_IMG_DIR/shot_1.jpg" -i "$TMP_IMG_DIR/shot_2.jpg" -i "$TMP_IMG_DIR/shot_3.jpg" \
                -i "$TMP_IMG_DIR/shot_4.jpg" -i "$TMP_IMG_DIR/shot_5.jpg" -i "$TMP_IMG_DIR/shot_6.jpg" -i "$TMP_IMG_DIR/shot_7.jpg" \
                -i "$TMP_IMG_DIR/shot_8.jpg" -i "$TMP_IMG_DIR/shot_9.jpg" -i "$TMP_IMG_DIR/shot_10.jpg" -i "$TMP_IMG_DIR/shot_11.jpg" \
                -i "$TMP_IMG_DIR/shot_12.jpg" -i "$TMP_IMG_DIR/shot_13.jpg" -i "$TMP_IMG_DIR/shot_14.jpg" -i "$TMP_IMG_DIR/shot_15.jpg" \
                -filter_complex "xstack=inputs=16:layout=0_0|w0_0|0_h0|w0_h0|0_h0*2|w0_h0*2|0_h0*3|w0_h0*3|0_h0*4|w0_h0*4|0_h0*5|w0_h0*5|0_h0*6|w0_h0*6|0_h0*7|w0_h0*7" -q:v 3 "$STITCHED_IMG" >> "$LOG_FILE" 2>&1
                [ -f "$STITCHED_IMG" ] && rm -f "$LOG_FILE"
            fi
        fi
        rm -rf "$TMP_IMG_DIR"
    fi
}

# 路由控制
if [ "$1" == "--auto" ]; then
    for dir in "$BASE_DIR"/*; do 
        [ -d "$dir" ] && process_folder "$(basename "$dir")"
    done 
elif [ "$1" == "--folder" ] && [ -n "$2" ]; then
    process_folder "$2"
fi
