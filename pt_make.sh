#!/bin/bash

# ==========================================
# 0. 首次运行初始化 (快捷唤醒)
# ==========================================
SCRIPT_PATH=$(readlink -f "$0") 
BASHRC="$HOME/.bashrc"

if ! grep -q "alias p='$SCRIPT_PATH'" "$BASHRC"; then
    echo "======================================"
    echo " ✨ 正在将本脚本注册为系统快捷指令 'p'..."
    echo "alias p='$SCRIPT_PATH'" >> "$BASHRC"
    echo " 🔄 正在自动刷新系统环境..."
    echo "======================================"
    sleep 2
    exec bash
fi

# --- 基础配置 ---
BASE_DIR="/home/docker/qbittorrent/downloads"
TRACKER="https://rousi.pro/tracker/808263a94ed47ca690395ca957b562e4/announce"

# ==========================================
# 核心处理函数 (把之前的逻辑封装起来)
# ==========================================
process_folder() {
    local FOLDER_NAME=$1
    local FOLDER_PATH="$BASE_DIR/$FOLDER_NAME"
    
    echo "------------------------------------------------"
    echo "📂 正在处理: $FOLDER_NAME"
    
    # 1. 净网行动
    find "$FOLDER_PATH" -type f \( -name "*.url" -o -name "*.txt" \) -delete
    find "$FOLDER_PATH" -type f -name "*.mp4" -size -50M -delete
    
    # 2. 去水印重命名
    for file in "$FOLDER_PATH"/*; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            if [[ "$filename" == *"@"* ]]; then
                newname="${filename#*@}"
                mv "$file" "$FOLDER_PATH/$newname"
            fi
        fi
    done

    # 3. 定位主视频
    VIDEO_PATH=$(find "$FOLDER_PATH" -maxdepth 1 -name "*.mp4" -type f -printf "%s\t%p\n" | sort -nr | head -n1 | cut -f2)
    if [ -z "$VIDEO_PATH" ]; then
        echo "⚠️  跳过：文件夹内没发现 mp4 视频。"
        return
    fi
    
    # 4. 智能计算分块大小
    SIZE_MB=$(du -sm "$FOLDER_PATH" | cut -f1)
    if [ "$SIZE_MB" -lt 512 ]; then PIECE_L=18
    elif [ "$SIZE_MB" -lt 1024 ]; then PIECE_L=19
    elif [ "$SIZE_MB" -lt 2048 ]; then PIECE_L=20
    elif [ "$SIZE_MB" -lt 4096 ]; then PIECE_L=21
    elif [ "$SIZE_MB" -lt 8192 ]; then PIECE_L=22
    elif [ "$SIZE_MB" -lt 16384 ]; then PIECE_L=23
    else PIECE_L=24
    fi

    # 5. 截图与参数
    ffmpeg -ss 00:05:00 -i "$VIDEO_PATH" -q:v 2 -frames:v 1 "$BASE_DIR/${FOLDER_NAME}_5min.jpg" -y > /dev/null 2>&1
    ffmpeg -ss 00:10:00 -i "$VIDEO_PATH" -q:v 2 -frames:v 1 "$BASE_DIR/${FOLDER_NAME}_10min.jpg" -y > /dev/null 2>&1
    ffmpeg -ss 00:15:00 -i "$VIDEO_PATH" -q:v 2 -frames:v 1 "$BASE_DIR/${FOLDER_NAME}_15min.jpg" -y > /dev/null 2>&1
    mediainfo "$VIDEO_PATH" > "$BASE_DIR/${FOLDER_NAME}_mediainfo.txt"

    # 6. 制作种子
    mktorrent -v -p -l "$PIECE_L" -a "$TRACKER" -o "$BASE_DIR/${FOLDER_NAME}.torrent" "$FOLDER_PATH"
    
    echo "✅ 处理完成：$FOLDER_NAME"
}

# ==========================================
# 主程序菜单
# ==========================================
echo "======================================"
echo "    🚀 PT 智能批量发种流水线 V3.0     "
echo "======================================"
echo " 1. 手动模式 (处理单个指定文件夹)"
echo " 2. 自动模式 (全盘扫描未做种资源)"
echo "======================================"
read -p "请选择运行模式 [1-2]: " RUN_MODE

if [ "$RUN_MODE" == "1" ]; then
    read -p "👉 请输入文件夹名称: " MANUAL_NAME
    process_folder "$MANUAL_NAME"
elif [ "$RUN_MODE" == "2" ]; then
    echo "🔍 正在扫描未做种资源..."
    found_any=false
    # 遍历下载目录下的所有文件夹
    for dir in "$BASE_DIR"/*; do
        if [ -d "$dir" ]; then
            folder_name=$(basename "$dir")
            # 判定标准：如果对应的 .torrent 文件不存在，则视为新资源
            if [ ! -f "$BASE_DIR/${folder_name}.torrent" ]; then
                found_any=true
                process_folder "$folder_name"
            fi
        fi
    done
    if [ "$found_any" = false ]; then
        echo "☕ 扫描完毕：所有文件夹均已制作过种子，无需处理。"
    fi
else
    echo "❌ 输入错误，脚本退出。"
fi