#!/bin/bash
# 强制设置基础环境变量
export LANG=zh_CN.UTF-8

# 从环境变量读取目录，Docker 内我们统一挂载到 /downloads
BASE_DIR="${BASE_DIR:-/downloads}"
TRACKER="https://rousi.pro/tracker/808263a94ed47ca690395ca957b562e4/announce"

process_folder() {
    local FOLDER_NAME=$1
    local FOLDER_PATH="$BASE_DIR/$FOLDER_NAME"
    local TORRENT_FILE="$BASE_DIR/${FOLDER_NAME}.torrent"
    local INFO_FILE="$BASE_DIR/${FOLDER_NAME}_mediainfo.txt"
    local STITCHED_IMG="$BASE_DIR/${FOLDER_NAME}_Stitched_4K.jpg"
    local TMP_IMG_DIR="/tmp/pt_screens_$(date +%s)"

    # 1. 终极防御：拦截 .!qB
    if find "$FOLDER_PATH" -type f -name "*.!qB" | grep -q .; then
        return
    fi

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

    if [ "$NEED_MAKE_TORRENT" = false ] && [ "$NEED_FFMPEG" = false ]; then
        return
    fi

    # 4. 制作种子与参数
    mapfile -t VIDEO_FILES < <(find "$FOLDER_PATH" -maxdepth 1 -iname "*.mp4" | sort)
    NUM_FILES=${#VIDEO_FILES[@]}
    
    if [ "$NEED_MAKE_TORRENT" = true ] && [ "$NUM_FILES" -gt 0 ]; then
        MAIN_VIDEO=$(find "$FOLDER_PATH" -maxdepth 1 -iname "*.mp4" -printf "%s\t%p\n" | sort -nr | head -n1 | cut -f2)
        [ -n "$MAIN_VIDEO" ] && mediainfo "$MAIN_VIDEO" > "$INFO_FILE"
        mktorrent -v -p -l 22 -a "$TRACKER" -o "$TORRENT_FILE" "$FOLDER_PATH" > /dev/null 2>&1
    fi

    # 5. 截图与拼合
    if [ "$NEED_FFMPEG" = true ] && [ "$NUM_FILES" -gt 0 ]; then
        mkdir -p "$TMP_IMG_DIR"
        MAX_JOBS=4
        LOG_FILE="$FOLDER_PATH/ffmpeg_debug.log"
        echo "开始提取截图..." > "$LOG_FILE"
        
        for i in {0..15}; do
            FILE_IDX=$(( i % NUM_FILES ))
            CUR_FILE="${VIDEO_FILES[$FILE_IDX]}"
            DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$CUR_FILE" | cut -d. -f1)
            [ -z "$DUR" ] && DUR=300
            TIMESTAMP=$(( DUR * (5 + i * 5) / 100 ))
            
            # 使用强制 1920x1080 居中补黑边算法，彻底消灭 xstack 像素对齐报错
            ( ffmpeg -y -ss "$TIMESTAMP" -i "$CUR_FILE" -frames:v 1 -q:v 2 \
              -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black" \
              "$TMP_IMG_DIR/shot_$i.jpg" >> "$LOG_FILE" 2>&1 ) &
            
            if [[ $(($((i + 1)) % $MAX_JOBS)) -eq 0 ]]; then wait; fi
        done
        wait

        # 二次校验防翻车：确保 16 张图一张没少
        MISSING=0
        for i in {0..15}; do
            if [ ! -f "$TMP_IMG_DIR/shot_$i.jpg" ]; then
                echo "❌ 错误：shot_$i.jpg 生成失败！" >> "$LOG_FILE"
                MISSING=1
            fi
        done

        if [ "$MISSING" -eq 0 ]; then
            echo "✅ 16张截图就绪，开始拼合 4K 巨幕..." >> "$LOG_FILE"
            ffmpeg -y \
            -i "$TMP_IMG_DIR/shot_0.jpg" -i "$TMP_IMG_DIR/shot_1.jpg" -i "$TMP_IMG_DIR/shot_2.jpg" -i "$TMP_IMG_DIR/shot_3.jpg" \
            -i "$TMP_IMG_DIR/shot_4.jpg" -i "$TMP_IMG_DIR/shot_5.jpg" -i "$TMP_IMG_DIR/shot_6.jpg" -i "$TMP_IMG_DIR/shot_7.jpg" \
            -i "$TMP_IMG_DIR/shot_8.jpg" -i "$TMP_IMG_DIR/shot_9.jpg" -i "$TMP_IMG_DIR/shot_10.jpg" -i "$TMP_IMG_DIR/shot_11.jpg" \
            -i "$TMP_IMG_DIR/shot_12.jpg" -i "$TMP_IMG_DIR/shot_13.jpg" -i "$TMP_IMG_DIR/shot_14.jpg" -i "$TMP_IMG_DIR/shot_15.jpg" \
            -filter_complex "xstack=grid=2x8:fill=black" -q:v 3 "$STITCHED_IMG" >> "$LOG_FILE" 2>&1
            
            if [ -f "$STITCHED_IMG" ]; then
                rm -f "$LOG_FILE" # 拼合成功，销毁日志文件（深藏功与名）
            else
                echo "❌ 拼合失败，请查看上方报错信息。" >> "$LOG_FILE"
            fi
        else
            echo "❌ 截图缺失，安全中断拼合。" >> "$LOG_FILE"
        fi
        
        rm -rf "$TMP_IMG_DIR"
    fi
