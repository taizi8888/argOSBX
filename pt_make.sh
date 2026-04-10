#!/bin/bash

# ==========================================
# 0. 基础配置
# ==========================================
BASE_DIR="/home/docker/qbittorrent/downloads"
TRACKER="https://rousi.pro/tracker/808263a94ed47ca690395ca957b562e4/announce"

process_folder() {
    local FOLDER_NAME=$1
    local FOLDER_PATH="$BASE_DIR/$FOLDER_NAME"
    local TORRENT_FILE="$BASE_DIR/${FOLDER_NAME}.torrent"
    local INFO_FILE="$BASE_DIR/${FOLDER_NAME}_mediainfo.txt"
    local STITCHED_IMG="$BASE_DIR/${FOLDER_NAME}_Stitched_4K.jpg"

    echo "------------------------------------------------"
    echo "📂 检查目录: $FOLDER_NAME"

    # 1. 基础清理与重命名
    find "$FOLDER_PATH" -type f \( -name "*.url" -o -name "*.txt" \) -delete > /dev/null 2>&1
    find "$FOLDER_PATH" -type f -name "*.mp4" -size -50M -delete > /dev/null 2>&1
    for file in "$FOLDER_PATH"/*; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            [[ "$filename" == *"@"* ]] && mv "$file" "$FOLDER_PATH/${filename#*@}"
        fi
    done

    # 2. 获取所有 mp4 文件列表
    mapfile -t VIDEO_FILES < <(find "$FOLDER_PATH" -maxdepth 1 -name "*.mp4" | sort)
    NUM_FILES=${#VIDEO_FILES[@]}

    if [ "$NUM_FILES" -eq 0 ]; then
        echo "⚠️  跳过：未发现视频文件。"
        return
    fi

    # 3. 增量判断
    [[ -f "$TORRENT_FILE" && -f "$INFO_FILE" && -f "$STITCHED_IMG" ]] && { echo "✅ 已完成，跳过。"; return; }

    # 4. 制作种子与参数 (以最大的文件作为 Mediainfo 参考)
    if [ ! -f "$TORRENT_FILE" ]; then
        echo "⏳ 正在制作种子与参数..."
        MAIN_VIDEO=$(find "$FOLDER_PATH" -maxdepth 1 -name "*.mp4" -printf "%s\t%p\n" | sort -nr | head -n1 | cut -f2)
        mediainfo "$MAIN_VIDEO" > "$INFO_FILE"
        SIZE_MB=$(du -sm "$FOLDER_PATH" | cut -f1)
        # 智能分块逻辑
        if [ "$SIZE_MB" -lt 512 ]; then PIECE_L=18
        elif [ "$SIZE_MB" -lt 1024 ]; then PIECE_L=19
        elif [ "$SIZE_MB" -lt 2048 ]; then PIECE_L=20
        elif [ "$SIZE_MB" -lt 4096 ]; then PIECE_L=21
        elif [ "$SIZE_MB" -lt 8192 ]; then PIECE_L=22
        elif [ "$SIZE_MB" -lt 16384 ]; then PIECE_L=23
        else PIECE_L=24; fi
        mktorrent -v -p -l "$PIECE_L" -a "$TRACKER" -o "$TORRENT_FILE" "$FOLDER_PATH" > /dev/null 2>&1
        echo "✅ 种子制作成功。"
    fi

    # 5. 核心逻辑：多文件平均分配 12 张截图 (2x6)
    if [ ! -f "$STITCHED_IMG" ]; then
        echo "⏳ 正在跨文件抽取 12 张截图制作 2x6 长图 (静默)..."
        
        FFMPEG_INPUTS=""
        FFMPEG_FILTERS=""
        COUNT=0

        # 分配算法：计算每个文件应该抓几张
        for (( i=0; i<12; i++ )); do
            FILE_IDX=$(( i % NUM_FILES ))
            CURRENT_FILE="${VIDEO_FILES[$FILE_IDX]}"
            
            # 获取该视频时长
            DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$CURRENT_FILE" | cut -d. -f1)
            
            # 在该视频中取一个点 (根据它是该文件的第几次抓取来决定时间点)
            # 计算这个文件被选中了几次
            INSTANCES_OF_FILE=0
            MY_POS=0
            for (( k=0; k<i; k++ )); do [ "${VIDEO_FILES[$((k%NUM_FILES))]}" == "$CURRENT_FILE" ] && ((MY_POS++)); done
            for (( k=0; k<12; k++ )); do [ "${VIDEO_FILES[$((k%NUM_FILES))]}" == "$CURRENT_FILE" ] && ((INSTANCES_OF_FILE++)); done
            
            # 均匀计算时间点 (5% 到 90% 之间)
            PERCENT=$(( 5 + (85 * (MY_POS + 1) / (INSTANCES_OF_FILE + 1)) ))
            TIMESTAMP=$(( DUR * PERCENT / 100 ))

            FFMPEG_INPUTS+="-ss $TIMESTAMP -i \"$CURRENT_FILE\" "
            FFMPEG_FILTERS+="[$COUNT:v]scale=1920:-1[v$COUNT];"
            ((COUNT++))
        done

        # 拼接最终滤镜字符串
        XSTACK_INPUTS=""
        for (( i=0; i<12; i++ )); do XSTACK_INPUTS+="[v$i]"; done
        
        # 执行拼接 (2x6 布局)
        eval "ffmpeg -y $FFMPEG_INPUTS -filter_complex \"${FFMPEG_FILTERS}${XSTACK_INPUTS}xstack=grid=2x6:fill=black\" -frames:v 1 -q:v 3 \"$STITCHED_IMG\"" > /dev/null 2>&1
        
        [[ -f "$STITCHED_IMG" ]] && echo "✅ 2x6 多文件长图制作成功。" || echo "❌ 长图制作失败。"
    fi
}

# ==========================================
# 菜单部分
# ==========================================
echo "======================================"
echo "   🚀 PT 多文件流水线 V3.9 (2x6全家福) "
echo "======================================"
echo " 1. 手动模式"
echo " 2. 自动批量扫描"
echo " 3. 退出"
echo "======================================"
read -p "选择模式 [1-3]: " RUN_MODE

case $RUN_MODE in
    1) read -p "👉 文件夹名: " MN; process_folder "$MN" ;;
    2) for dir in "$BASE_DIR"/*; do [ -d "$dir" ] && process_folder "$(basename "$dir")"; done ;;
    3|q|Q) exit 0 ;;
    *) echo "❌ 错误"; exit 1 ;;
esac