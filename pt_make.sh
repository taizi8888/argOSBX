#!/bin/bash

# 强制设置基础环境变量
export LANG=zh_CN.UTF-8

# ==========================================
# 0. 首次运行初始化 (彻底解决 Pipe 别名失效问题)
# ==========================================
# 如果当前运行的不是 /usr/local/bin/p，说明是从网络 curl 或者其他地方启动的
if [ ! -f "/usr/local/bin/p" ] || [ "$(readlink -f "$0")" != "/usr/local/bin/p" ]; then
    echo "======================================"
    echo " ✨ 正在将脚本固化为系统全局指令 'p'..."
    
    # 强制清理老版本在 bashrc 里留下的 alias 垃圾，防止冲突
    sed -i '/alias p=/d' "$HOME/.bashrc"
    
    # 从云端拉取最新代码，过滤乱码，并直接写入系统执行目录
    curl -Ls https://raw.githubusercontent.com/taizi8888/argOSBX/main/pt_make.sh | tr -d '\r' > /usr/local/bin/p
    chmod +x /usr/local/bin/p
    
    echo " ✅ 固化成功！正在为您自动启动..."
    echo "======================================"
    sleep 1
    exec /usr/local/bin/p
fi

# ==========================================
# 0.5 环境自检与自动修复 (针对新机器)
# ==========================================
check_env() {
    local missing=()
    command -v mediainfo >/dev/null 2>&1 || missing+=("mediainfo")
    command -v mktorrent >/dev/null 2>&1 || missing+=("mktorrent")
    command -v ffmpeg >/dev/null 2>&1 || missing+=("ffmpeg")
    command -v ffprobe >/dev/null 2>&1 || missing+=("ffmpeg") 
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo "======================================"
        echo " ⚠️ 检测到新机器缺失核心组件: ${missing[*]}"
        echo " ⏳ 正在自动为您呼叫支援安装，请稍候..."
        echo "======================================"
        sudo apt-get update -y > /dev/null 2>&1
        sudo apt-get install -y mediainfo mktorrent ffmpeg > /dev/null 2>&1
        echo " ✅ 环境装配完毕！弹药已上膛 🚀"
        echo "--------------------------------------"
    fi
}
check_env

# --- 基础配置 ---
BASE_DIR="/home/docker/qbittorrent/downloads"
TRACKER="https://rousi.pro/tracker/808263a94ed47ca690395ca957b562e4/announce"
TMP_IMG_DIR="/tmp/pt_screens_$(date +%s)"

# ==========================================
# 0.8 在线更新功能 (适配固化路径)
# ==========================================
update_script() {
    echo "⏳ 正在从云端获取最新版本..."
    if curl -Ls https://raw.githubusercontent.com/taizi8888/argOSBX/main/pt_make.sh | tr -d '\r' > /usr/local/bin/p; then
        chmod +x /usr/local/bin/p
        echo "✅ 更新成功！正在重新启动脚本..."
        sleep 1
        exec /usr/local/bin/p
    else
        echo "❌ 更新失败，请检查网络连接。"
    fi
}

process_folder() {
    local FOLDER_NAME=$1
    local FOLDER_PATH="$BASE_DIR/$FOLDER_NAME"
    local TORRENT_FILE="$BASE_DIR/${FOLDER_NAME}.torrent"
    local INFO_FILE="$BASE_DIR/${FOLDER_NAME}_mediainfo.txt"
    local STITCHED_IMG="$BASE_DIR/${FOLDER_NAME}_Stitched_4K.jpg"

    echo "------------------------------------------------"
    echo "📂 检查目录: $FOLDER_NAME"

    # 1. 终极防御：拦截 .!qB
    if find "$FOLDER_PATH" -type f -name "*.!qB" | grep -q .; then
        echo "🚧 拦截：该目录仍在下载中 (检测到 .!qB 文件)，跳过处理。"
        return
    fi

    # 2. 净网与去水印逻辑
    find "$FOLDER_PATH" -type f \( -iname "*.url" -o -iname "*.txt" -o -iname "*.nfo" -o -iname "*.lnk" -o -iname "*.html" -o -iname "*.htm" -o -iname "*.exe" -o -iname "*.bat" -o -iname "*.cmd" -o -iname "*.vbs" -o -iname "*.chm" \) -delete > /dev/null 2>&1
    find "$FOLDER_PATH" -type f -iname "*.mp4" -size -50M -delete > /dev/null 2>&1
    for file in "$FOLDER_PATH"/*; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            if [[ "$filename" == *"@"* ]]; then
                mv "$file" "$FOLDER_PATH/${filename#*@}"
            fi
        fi
    done

    # 3. 定位视频
    mapfile -t VIDEO_FILES < <(find "$FOLDER_PATH" -maxdepth 1 -iname "*.mp4" | sort)
    NUM_FILES=${#VIDEO_FILES[@]}
    if [ "$NUM_FILES" -eq 0 ]; then
        echo "⚠️  跳过：未发现 mp4 视频。"
        return
    fi

    # 4. 增量判断
    local NEED_MAKE_TORRENT=true
    local NEED_FFMPEG=true
    [[ -f "$TORRENT_FILE" && -f "$INFO_FILE" ]] && NEED_MAKE_TORRENT=false
    [[ -f "$STITCHED_IMG" ]] && NEED_FFMPEG=false

    if [ "$NEED_MAKE_TORRENT" = false ] && [ "$NEED_FFMPEG" = false ]; then
        echo "✅ 种子、参数、预览图均已存在，跳过该目录。"
        return
    fi

    # 5. 制作种子与参数
    if [ "$NEED_MAKE_TORRENT" = true ]; then
        echo "⏳ 正在制作纯净版种子与参数..."
        MAIN_VIDEO=$(find "$FOLDER_PATH" -maxdepth 1 -iname "*.mp4" -printf "%s\t%p\n" | sort -nr | head -n1 | cut -f2)
        [ -n "$MAIN_VIDEO" ] && mediainfo "$MAIN_VIDEO" > "$INFO_FILE"
        
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
        if [[ -f "$TORRENT_FILE" && -f "$INFO_FILE" ]]; then
            echo "✅ 种子与参数制作成功。"
        else
            echo "❌ 制作失败。"
        fi
    fi

    # 6. 核心修改：16张截图 + 并发4 + 2x8 拼合
    if [ "$NEED_FFMPEG" = true ]; then
        echo "⏳ 正在静默提取 16 张截图 (并发数: 4)..."
        mkdir -p "$TMP_IMG_DIR"
        MAX_JOBS=4  
        
        for i in {0..15}; do
            FILE_IDX=$(( i % NUM_FILES ))
            CUR_FILE="${VIDEO_FILES[$FILE_IDX]}"
            DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$CUR_FILE" | cut -d. -f1)
            [ -z "$DUR" ] && DUR=300
            
            INSTANCES=0; MY_POS=0
            for ((k=0; k<i; k++)); do [ "${VIDEO_FILES[$((k%NUM_FILES))]}" == "$CUR_FILE" ] && ((MY_POS++)); done
            for ((k=0; k<16; k++)); do [ "${VIDEO_FILES[$((k%NUM_FILES))]}" == "$CUR_FILE" ] && ((INSTANCES++)); done
            PERCENT=$(( 5 + (85 * (MY_POS + 1) / (INSTANCES + 1)) ))
            TIMESTAMP=$(( DUR * PERCENT / 100 ))

            ( ffmpeg -y -ss "$TIMESTAMP" -i "$CUR_FILE" -frames:v 1 -q:v 2 -vf "scale=1920:-1" "$TMP_IMG_DIR/shot_$i.jpg" > /dev/null 2>&1 ) &
            
            if [[ $(($((i + 1)) % $MAX_JOBS)) -eq 0 ]]; then
                wait
            fi
        done
        wait

        echo "⏳ 正在拼合 2x8 规格 4K 巨幕预览长图..."
        ffmpeg -y \
        -i "$TMP_IMG_DIR/shot_0.jpg" -i "$TMP_IMG_DIR/shot_1.jpg" -i "$TMP_IMG_DIR/shot_2.jpg" -i "$TMP_IMG_DIR/shot_3.jpg" \
        -i "$TMP_IMG_DIR/shot_4.jpg" -i "$TMP_IMG_DIR/shot_5.jpg" -i "$TMP_IMG_DIR/shot_6.jpg" -i "$TMP_IMG_DIR/shot_7.jpg" \
        -i "$TMP_IMG_DIR/shot_8.jpg" -i "$TMP_IMG_DIR/shot_9.jpg" -i "$TMP_IMG_DIR/shot_10.jpg" -i "$TMP_IMG_DIR/shot_11.jpg" \
        -i "$TMP_IMG_DIR/shot_12.jpg" -i "$TMP_IMG_DIR/shot_13.jpg" -i "$TMP_IMG_DIR/shot_14.jpg" -i "$TMP_IMG_DIR/shot_15.jpg" \
        -filter_complex "xstack=grid=2x8:fill=black" -q:v 3 "$STITCHED_IMG" > /dev/null 2>&1
        
        rm -rf "$TMP_IMG_DIR"
        [[ -f "$STITCHED_IMG" ]] && echo "✅ 2x8 预览长图制作成功！" || echo "❌ 制作失败。"
    fi
}

# ==========================================
# 主菜单
# ==========================================
echo "======================================"
echo " 🚀 PT 终极自愈流水线 V4.6 (固化防丢版)"
echo "======================================"
echo " 1. 手动模式 (处理单个文件夹)"
echo " 2. 自动模式 (全盘增量扫描)"
echo " 3. 🔄 在线更新脚本 (云端同步)"
echo " 4. 退出脚本"
echo "======================================"
read -p "选择模式 [1-4]: " RUN_MODE
case $RUN_MODE in
    1) read -p "文件夹名: " MN; process_folder "$MN" ;;
    2) 
        for dir in "$BASE_DIR"/*; do 
            [ -d "$dir" ] && process_folder "$(basename "$dir")"
        done 
        ;;
    3) update_script ;;
    4|q|Q) exit 0 ;;
esac
