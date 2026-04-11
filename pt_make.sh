#!/bin/bash

# ==========================================
# 0. 首次运行初始化 (自动注册快捷键 p)
# ==========================================
SCRIPT_PATH=$(readlink -f "$0") 
BASHRC="$HOME/.bashrc"

if ! grep -q "alias p='$SCRIPT_PATH'" "$BASHRC"; then
    echo "======================================"
    echo " ✨ 正在将脚本注册为系统快捷指令 'p'..."
    echo "alias p='$SCRIPT_PATH'" >> "$BASHRC"
    echo " 🔄 正在刷新环境，完成后请重新输入 p 运行"
    echo "======================================"
    sleep 2
    exec bash
fi

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

    # 1. 终极防御：检查是否仍在下载中 (.!qB 雷达)
    if find "$FOLDER_PATH" -type f -name "*.!qB" | grep -q .; then
        echo "🚧 拦截：该目录仍在下载中 (检测到 .!qB 文件)，跳过处理。"
        return
    fi

    # 2. 军用级净网行动：无情删光所有常见小广告格式 (-iname 忽略大小写)
    find "$FOLDER_PATH" -type f \( -iname "*.url" -o -iname "*.txt" -o -iname "*.nfo" -o -iname "*.lnk" -o -iname "*.html" -o -iname "*.htm" -o -iname "*.exe" -o -iname "*.bat" -o -iname "*.cmd" -o -iname "*.vbs" -o -iname "*.chm" \) -delete > /dev/null 2>&1
    
    # 清理小于 50MB 的广告小视频
    find "$FOLDER_PATH" -type f -iname "*.mp4" -size -50M -delete > /dev/null 2>&1
    
    # 文件名去水印：清理带有 @ 及前面部分的名字 (例如 xxx@video.mp4 -> video.mp4)
    for file in "$FOLDER_PATH"/*; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            if [[ "$filename" == *"@"* ]]; then
                mv "$file" "$FOLDER_PATH/${filename#*@}"
            fi
        fi
    done

    # 3. 定位所有视频文件 (支持多文件全家福)
    mapfile -t VIDEO_FILES < <(find "$FOLDER_PATH" -maxdepth 1 -iname "*.mp4" | sort)
    NUM_FILES=${#VIDEO_FILES[@]}
    if [ "$NUM_FILES" -eq 0 ]; then
        echo "⚠️  跳过：未发现 mp4 视频。"
        return
    fi

    # 4. 智能增量判断 (有了就不做)
    local NEED_MAKE_TORRENT=true
    local NEED_FFMPEG=true
    [[ -f "$TORRENT_FILE" && -f "$INFO_FILE" ]] && NEED_MAKE_TORRENT=false
    [[ -f "$STITCHED_IMG" ]] && NEED_FFMPEG=false

    if [ "$NEED_MAKE_TORRENT" = false ] && [ "$NEED_FFMPEG" = false ]; then
        echo "✅ 种子、参数、预览图均已存在，跳过该目录。"
        return
    fi

    # 5. 补全种子与参数 (智能计算分块)
    if [ "$NEED_MAKE_TORRENT" = true ]; then
        echo "⏳ 正在制作纯净版种子与参数..."
        # 找最大的视频文件用来提取 mediainfo
        MAIN_VIDEO=$(find "$FOLDER_PATH" -maxdepth 1 -iname "*.mp4" -printf "%s\t%p\n" | sort -nr | head -n1 | cut -f2)
        mediainfo "$MAIN_VIDEO" > "$INFO_FILE"
        
        # 智能分块大小计算
        SIZE_MB=$(du -sm "$FOLDER_PATH" | cut -f1)
        if [ "$SIZE_MB" -lt 512 ]; then PIECE_L=18
        elif [ "$SIZE_MB" -lt 1024 ]; then PIECE_L=19
        elif [ "$SIZE_MB" -lt 2048 ]; then PIECE_L=20
        elif [ "$SIZE_MB" -lt 4096 ]; then PIECE_L=21
        elif [ "$SIZE_MB" -lt 8192 ]; then PIECE_L=22
        elif [ "$SIZE_MB" -lt 16384 ]; then PIECE_L=23
        else PIECE_L=24
        fi
        
        mktorrent -v -p -l "$PIECE_L" -a "$TRACKER" -o "$TORRENT_FILE" "$FOLDER_PATH" > /dev/null 2>&1
        echo "✅ 种子与参数制作成功。"
    else
        echo "⏩ 种子与参数已存在，跳过制作。"
    fi

    # 6. 核心：小批量并发防崩溃截图 (3个一组，共12张，多文件自动摊派)
    if [ "$NEED_FFMPEG" = true ]; then
        echo "⏳ 正在静默提取 12 张 8K 截图 (防宕机并发模式)..."
        mkdir -p "$TMP_IMG_DIR"
        MAX_JOBS=4  # 黄金并发数
        
        for i in {0..11}; do
            FILE_IDX=$(( i % NUM_FILES ))
            CUR_FILE="${VIDEO_FILES[$FILE_IDX]}"
            DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$CUR_FILE" | cut -d. -f1)
            
            # 智能分配时间点，避开片头片尾黑屏
            INSTANCES=0; MY_POS=0
            for ((k=0; k<i; k++)); do [ "${VIDEO_FILES[$((k%NUM_FILES))]}" == "$CUR_FILE" ] && ((MY_POS++)); done
            for ((k=0; k<12; k++)); do [ "${VIDEO_FILES[$((k%NUM_FILES))]}" == "$CUR_FILE" ] && ((INSTANCES++)); done
            PERCENT=$(( 5 + (85 * (MY_POS + 1) / (INSTANCES + 1)) ))
            TIMESTAMP=$(( DUR * PERCENT / 100 ))

            # 后台截取并强制缩放到 1920 宽
            ( ffmpeg -y -ss "$TIMESTAMP" -i "$CUR_FILE" -frames:v 1 -q:v 2 -vf "scale=1920:-1" "$TMP_IMG_DIR/shot_$i.jpg" > /dev/null 2>&1 ) &
            
            # 满 3 个任务就同步等待，保护内存
            if [[ $(($((i + 1)) % $MAX_JOBS)) -eq 0 ]]; then
                echo -n "   - 同步处理第 $((i-1)) 到 $((i+1)) 张... "
                wait; echo "完成"
            fi
        done
        wait # 等待最后一组完成

        echo "⏳ 正在拼合 2x6 规格 4K 巨幕预览长图..."
        ffmpeg -y \
        -i "$TMP_IMG_DIR/shot_0.jpg" -i "$TMP_IMG_DIR/shot_1.jpg" -i "$TMP_IMG_DIR/shot_2.jpg" -i "$TMP_IMG_DIR/shot_3.jpg" \
        -i "$TMP_IMG_DIR/shot_4.jpg" -i "$TMP_IMG_DIR/shot_5.jpg" -i "$TMP_IMG_DIR/shot_6.jpg" -i "$TMP_IMG_DIR/shot_7.jpg" \
        -i "$TMP_IMG_DIR/shot_8.jpg" -i "$TMP_IMG_DIR/shot_9.jpg" -i "$TMP_IMG_DIR/shot_10.jpg" -i "$TMP_IMG_DIR/shot_11.jpg" \
        -filter_complex "xstack=grid=2x6:fill=black" -q:v 3 "$STITCHED_IMG" > /dev/null 2>&1
        
        # 打扫战场
        rm -rf "$TMP_IMG_DIR"
        [[ -f "$STITCHED_IMG" ]] && echo "✅ 2x6 预览长图制作成功！" || echo "❌ 预览图制作失败。"
    else
        echo "⏩ 预览图已存在，跳过截图。"
    fi
}

# ==========================================
# 主程序菜单
# ==========================================
echo "======================================"
echo " 🚀 PT 终极洗版机 V4.4 (极净无码版) "
echo "======================================"
echo " 1. 手动模式 (处理单个文件夹)"
echo " 2. 自动模式 (全盘扫描，自动跳过未完成)"
echo " 3. 退出脚本"
echo "======================================"
read -p "请选择模式 [1-3]: " RUN_MODE
case $RUN_MODE in
    1) read -p "👉 请输入文件夹名: " MN; process_folder "$MN" ;;
    2) 
        echo "🔍 正在扫描下载目录..."
        for dir in "$BASE_DIR"/*; do 
            [ -d "$dir" ] && process_folder "$(basename "$dir")"
        done 
        ;;
    3|q|Q) echo "👋 已退出。"; exit 0 ;;
    *) echo "❌ 输入错误。"; exit 1 ;;
esac