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

# ==========================================
# 核心处理函数：增量模式
# ==========================================
process_folder() {
    local FOLDER_NAME=$1
    local FOLDER_PATH="$BASE_DIR/$FOLDER_NAME"
    
    # 定义产出文件路径
    local TORRENT_FILE="$BASE_DIR/${FOLDER_NAME}.torrent"
    local INFO_FILE="$BASE_DIR/${FOLDER_NAME}_mediainfo.txt"
    local STITCHED_IMG="$BASE_DIR/${FOLDER_NAME}_Stitched_4K.jpg"

    echo "------------------------------------------------"
    echo "📂 检查目录: $FOLDER_NAME"

    # 1. 基础清理与重命名 (操作极快，每次运行都执行以确保纯净)
    find "$FOLDER_PATH" -type f \( -name "*.url" -o -name "*.txt" \) -delete
    find "$FOLDER_PATH" -type f -name "*.mp4" -size -50M -delete > /dev/null 2>&1
    for file in "$FOLDER_PATH"/*; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            [[ "$filename" == *"@"* ]] && mv "$file" "$FOLDER_PATH/${filename#*@}"
        fi
    done

    # 2. 定位主视频
    VIDEO_PATH=$(find "$FOLDER_PATH" -maxdepth 1 -name "*.mp4" -type f -printf "%s\t%p\n" | sort -nr | head -n1 | cut -f2)
    if [ -z "$VIDEO_PATH" ]; then
        echo "⚠️  跳过：文件夹内没发现 mp4 视频。"
        return
    fi

    # 3. 核心判断逻辑
    local NEED_MAKE_TORRENT=true
    local NEED_FFMPEG=true

    [[ -f "$TORRENT_FILE" && -f "$INFO_FILE" ]] && NEED_MAKE_TORRENT=false
    [[ -f "$STITCHED_IMG" ]] && NEED_FFMPEG=false

    # 如果全都有了，直接跳过
    if [ "$NEED_MAKE_TORRENT" = false ] && [ "$NEED_FFMPEG" = false ]; then
        echo "✅ 种子、参数、预览图均已存在，跳过该目录。"
        return
    fi

    # --- 开始增量处理 ---

    # 补做 Mediainfo 和 种子
    if [ "$NEED_MAKE_TORRENT" = true ]; then
        echo "⏳ 正在补做 Mediainfo 和 种子文件..."
        mediainfo "$VIDEO_PATH" > "$INFO_FILE"
        
        # 计算分块
        SIZE_MB=$(du -sm "$FOLDER_PATH" | cut -f1)
        if [ "$SIZE_MB" -lt 512 ]; then PIECE_L=18
        elif [ "$SIZE_MB" -lt 1024 ]; then PIECE_L=19
        elif [ "$SIZE_MB" -lt 2048 ]; then PIECE_L=20
        elif [ "$SIZE_MB" -lt 4096 ]; then PIECE_L=21
        elif [ "$SIZE_MB" -lt 8192 ]; then PIECE_L=22
        elif [ "$SIZE_MB" -lt 16384 ]; then PIECE_L=23
        else PIECE_L=24
        fi
        
        mktorrent -v -p -l "$PIECE_L" -a "$TRACKER" -o "$TORRENT_FILE" "$FOLDER_PATH"
        echo "✅ 种子与参数补全成功。"
    else
        echo "⏩ 种子与参数已存在，跳过制作。"
    fi

    # 补做图片 (使用 V3.6 闪电截图逻辑)
    if [ "$NEED_FFMPEG" = true ]; then
        echo "⏳ 正在补抓 2x3 规格 4K 预览长图..."
        DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO_PATH" | cut -d. -f1)
        if [ -n "$DURATION" ] && [ "$DURATION" -gt 60 ]; then
            T1=$((DURATION * 10 / 100)); T2=$((DURATION * 25 / 100)); T3=$((DURATION * 40 / 100))
            T4=$((DURATION * 55 / 100)); T5=$((DURATION * 70 / 100)); T6=$((DURATION * 85 / 100))
            
            ffmpeg -y -ss "$T1" -i "$VIDEO_PATH" -ss "$T2" -i "$VIDEO_PATH" -ss "$T3" -i "$VIDEO_PATH" \
                      -ss "$T4" -i "$VIDEO_PATH" -ss "$T5" -i "$VIDEO_PATH" -ss "$T6" -i "$VIDEO_PATH" \
            -filter_complex "[0:v]scale=1920:-1[v1];[1:v]scale=1920:-1[v2];[2:v]scale=1920:-1[v3];[3:v]scale=1920:-1[v4];[4:v]scale=1920:-1[v5];[5:v]scale=1920:-1[v6];[v1][v2][v3][v4][v5][v6]xstack=grid=2x3:fill=black" \
            -frames:v 1 -q:v 3 "$STITCHED_IMG"
            
            [[ -f "$STITCHED_IMG" ]] && echo "✅ 4K 预览长图补抓成功。" || echo "❌ 预览图补抓失败。"
        else
            echo "⚠️  视频时长不足，无法补抓图片。"
        fi
    else
        echo "⏩ 预览图已存在，跳过截图。"
    fi

    echo "🎉 处理完毕: $FOLDER_NAME"
}

# ==========================================
# 主程序菜单
# ==========================================
echo "======================================"
echo "    🚀 PT 智能增量发种流水线 V3.7     "
echo "======================================"
echo " 1. 手动模式 (处理单个文件夹)"
echo " 2. 自动模式 (全盘扫描缺漏资源)"
echo " 3. 退出脚本"
echo "======================================"
read -p "请选择模式 [1-3]: " RUN_MODE

case $RUN_MODE in
    1)
        read -p "👉 请输入文件夹名称: " MANUAL_NAME
        process_folder "$MANUAL_NAME" ;;
    2)
        echo "🔍 正在扫描需要补齐的资源..."
        found_any=false
        for dir in "$BASE_DIR"/*; do
            if [ -d "$dir" ]; then
                folder_name=$(basename "$dir")
                process_folder "$folder_name"
                found_any=true
            fi
        done
        [ "$found_any" = false ] && echo "☕ 下载目录为空。" ;;
    3|q|Q)
        echo "👋 已退出。"
        exit 0 ;;
    *)
        echo "❌ 输入错误。"
        exit 1 ;;
esac