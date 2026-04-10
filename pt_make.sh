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
# 核心处理函数
# ==========================================
process_folder() {
    local FOLDER_NAME=$1
    local FOLDER_PATH="$BASE_DIR/$FOLDER_NAME"
    
    echo "------------------------------------------------"
    echo "📂 正在处理: $FOLDER_NAME"
    
    # 1. 净网行动：删除广告和垃圾小视频
    find "$FOLDER_PATH" -type f \( -name "*.url" -o -name "*.txt" \) -delete
    find "$FOLDER_PATH" -type f -name "*.mp4" -size -50M -delete
    
    # 2. 去水印：清理文件名中 @ 及其前面的广告词
    for file in "$FOLDER_PATH"/*; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            if [[ "$filename" == *"@"* ]]; then
                newname="${filename#*@}"
                mv "$file" "$FOLDER_PATH/$newname"
            fi
        fi
    done

    # 3. 智能定位主视频（体积最大的 mp4）
    VIDEO_PATH=$(find "$FOLDER_PATH" -maxdepth 1 -name "*.mp4" -type f -printf "%s\t%p\n" | sort -nr | head -n1 | cut -f2)
    if [ -z "$VIDEO_PATH" ]; then
        echo "⚠️  跳过：文件夹内没发现 mp4 视频。"
        return
    fi
    
    # 4. 智能计算分块大小 (-l)
    SIZE_MB=$(du -sm "$FOLDER_PATH" | cut -f1)
    if [ "$SIZE_MB" -lt 512 ]; then PIECE_L=18
    elif [ "$SIZE_MB" -lt 1024 ]; then PIECE_L=19
    elif [ "$SIZE_MB" -lt 2048 ]; then PIECE_L=20
    elif [ "$SIZE_MB" -lt 4096 ]; then PIECE_L=21
    elif [ "$SIZE_MB" -lt 8192 ]; then PIECE_L=22
    elif [ "$SIZE_MB" -lt 16384 ]; then PIECE_L=23
    else PIECE_L=24
    fi

    # 5. 提取 Mediainfo 参数
    mediainfo "$VIDEO_PATH" > "$BASE_DIR/${FOLDER_NAME}_mediainfo.txt"

    # 6. 核心魔法：均匀抓取 6 张图并拼成 2x3 网格大图
    # 这里的逻辑：跳过前 5% 防止黑屏，之后每隔一段时间抓一张，共 6 张，拼成总宽 3840 像素(4K)的图
    echo "⏳ 正在生成 2x3 规格 4K 预览长图..."
    STITCHED_IMG="$BASE_DIR/${FOLDER_NAME}_Stitched_4K.jpg"
    
    # 使用 select 滤镜均匀采样 6 帧，缩放每张到 1920 宽，拼成 2x3
    ffmpeg -i "$VIDEO_PATH" -vf "select='not(mod(n\,max(1\,TRUNC(V/6))))',scale=1920:-1,tile=2x3" -frames:v 1 -q:v 3 "$STITCHED_IMG" -y > /dev/null 2>&1

    # 7. 制作种子
    mktorrent -v -p -l "$PIECE_L" -a "$TRACKER" -o "$BASE_DIR/${FOLDER_NAME}.torrent" "$FOLDER_PATH"
    
    echo "✅ 处理完成：$FOLDER_NAME"
}

# ==========================================
# 主程序菜单
# ==========================================
echo "======================================"
echo "    🚀 PT 智能批量发种流水线 V3.5     "
echo "======================================"
echo " 1. 手动模式 (处理单个文件夹)"
echo " 2. 自动模式 (全盘批量扫描)"
echo " 3. 退出脚本"
echo "======================================"
read -p "请选择模式 [1-3]: " RUN_MODE

case $RUN_MODE in
    1)
        read -p "👉 请输入文件夹名称: " MANUAL_NAME
        process_folder "$MANUAL_NAME"
        ;;
    2)
        echo "🔍 正在扫描未做种资源..."
        found_any=false
        for dir in "$BASE_DIR"/*; do
            if [ -d "$dir" ]; then
                folder_name=$(basename "$dir")
                if [ ! -f "$BASE_DIR/${folder_name}.torrent" ]; then
                    found_any=true
                    process_folder "$folder_name"
                fi
            fi
        done
        [ "$found_any" = false ] && echo "☕ 所有文件夹均已处理。"
        ;;
    3|q|Q)
        echo "👋 已退出。"
        exit 0
        ;;
    *)
        echo "❌ 输入错误。"
        exit 1
        ;;
esac