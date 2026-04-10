#!/bin/bash

# --- 基础配置 ---
BASE_DIR="/home/docker/qbittorrent/downloads"
TRACKER="https://rousi.pro/tracker/808263a94ed47ca690395ca957b562e4/announce"
TMP_IMG_DIR="/tmp/pt_screens_$(date +%s)"

process_folder() {
    local FOLDER_NAME=$1
    local FOLDER_PATH="$BASE_DIR/$FOLDER_NAME"
    local TORRENT_FILE="$BASE_DIR/${FOLDER_NAME}.torrent"
    local INFO_FILE="$BASE_DIR/${FOLDER_NAME}_mediainfo.txt"
    local STITCHED_IMG="$BASE_DIR/${FOLDER_NAME}_Stitched_4K.jpg"

    echo "------------------------------------------------"
    echo "📂 检查目录: $FOLDER_NAME"

    # 1. 增量判断
    [[ -f "$TORRENT_FILE" && -f "$INFO_FILE" && -f "$STITCHED_IMG" ]] && { echo "✅ 已完成，跳过。"; return; }

    # 2. 定位视频
    mapfile -t VIDEO_FILES < <(find "$FOLDER_PATH" -maxdepth 1 -name "*.mp4" | sort)
    NUM_FILES=${#VIDEO_FILES[@]}
    [ "$NUM_FILES" -eq 0 ] && { echo "⚠️  未发现视频。"; return; }

    # 3. 制作种子逻辑 (略，保持 V4.0 逻辑)
    # ...

    # 4. 核心：小批量并发截图 (3个一组)
    if [ ! -f "$STITCHED_IMG" ]; then
        echo "⏳ 正在执行“小批量并发”：每 3 张一组，共 12 张..."
        mkdir -p "$TMP_IMG_DIR"
        
        MAX_JOBS=3  # 设置并发数为 3
        
        for i in {0..11}; do
            FILE_IDX=$(( i % NUM_FILES ))
            CUR_FILE="${VIDEO_FILES[$FILE_IDX]}"
            DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$CUR_FILE" | cut -d. -f1)
            
            # 分配时间点
            INSTANCES=0; MY_POS=0
            for ((k=0; k<i; k++)); do [ "${VIDEO_FILES[$((k%NUM_FILES))]}" == "$CUR_FILE" ] && ((MY_POS++)); done
            for ((k=0; k<12; k++)); do [ "${VIDEO_FILES[$((k%NUM_FILES))]}" == "$CUR_FILE" ] && ((INSTANCES++)); done
            PERCENT=$(( 5 + (85 * (MY_POS + 1) / (INSTANCES + 1)) ))
            TIMESTAMP=$(( DUR * PERCENT / 100 ))

            # 后台运行 ffmpeg
            (
                ffmpeg -y -ss "$TIMESTAMP" -i "$CUR_FILE" -frames:v 1 -q:v 2 -vf "scale=1920:-1" "$TMP_IMG_DIR/shot_$i.jpg" > /dev/null 2>&1
            ) &
            
            # 每达到 MAX_JOBS 个后台任务，就等待它们完成
            if [[ $(($((i + 1)) % $MAX_JOBS)) -eq 0 ]]; then
                echo -n "⏳ 正在同步处理第 $((i-1))-$((i+1)) 张... "
                wait
                echo "OK"
            fi
        done
        wait # 确保最后一组也抓完

        # 5. 最后合并
        echo "⏳ 正在合成 2x6 最终长图..."
        ffmpeg -y \
        -i "$TMP_IMG_DIR/shot_0.jpg" -i "$TMP_IMG_DIR/shot_1.jpg" -i "$TMP_IMG_DIR/shot_2.jpg" -i "$TMP_IMG_DIR/shot_3.jpg" \
        -i "$TMP_IMG_DIR/shot_4.jpg" -i "$TMP_IMG_DIR/shot_5.jpg" -i "$TMP_IMG_DIR/shot_6.jpg" -i "$TMP_IMG_DIR/shot_7.jpg" \
        -i "$TMP_IMG_DIR/shot_8.jpg" -i "$TMP_IMG_DIR/shot_9.jpg" -i "$TMP_IMG_DIR/shot_10.jpg" -i "$TMP_IMG_DIR/shot_11.jpg" \
        -filter_complex "xstack=grid=2x6:fill=black" -q:v 3 "$STITCHED_IMG" > /dev/null 2>&1
        
        rm -rf "$TMP_IMG_DIR"
        echo "✅ 2x6 长图制作成功！"
    fi
}
# 菜单部分略...