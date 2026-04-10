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

# ==========================================
# 1. 核心运行逻辑：洗版 + 智能分块 + 发种
# ==========================================

BASE_DIR="/home/docker/qbittorrent/downloads"
TRACKER="https://rousi.pro/tracker/808263a94ed47ca690395ca957b562e4/announce"

echo "======================================"
echo "    🚀 PT 纯净洗版 + 智能分块流水线    "
echo "======================================"

read -p "👉 请输入要处理的【文件夹名称】 (例如 savr-1022): " FOLDER_NAME

FOLDER_PATH="$BASE_DIR/$FOLDER_NAME"

if [ ! -d "$FOLDER_PATH" ]; then
    echo "❌ 错误：找不到文件夹 $FOLDER_PATH ，请检查拼写！"
    exit 1
fi

echo " "
echo "⏳ [1/6] 正在执行“净网行动”：删除广告和垃圾文件..."
find "$FOLDER_PATH" -type f -name "*.url" -delete
find "$FOLDER_PATH" -type f -name "*.txt" -delete
find "$FOLDER_PATH" -type f -name "*.mp4" -size -50M -delete
echo "✅ 垃圾文件清理完毕！"

echo " "
echo "⏳ [2/6] 正在执行“去水印”：自动清理文件名广告前缀..."
for file in "$FOLDER_PATH"/*; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        if [[ "$filename" == *"@"* ]]; then
            newname="${filename#*@}"
            mv "$file" "$FOLDER_PATH/$newname"
            echo "   🔄 重命名: $filename -> $newname"
        fi
    fi
done
echo "✅ 文件名净化完毕！"

echo " "
echo "⏳ [3/6] 正在智能定位主视频文件..."
VIDEO_PATH=$(find "$FOLDER_PATH" -maxdepth 1 -name "*.mp4" -type f -printf "%s\t%p\n" | sort -nr | head -n1 | cut -f2)

if [ -z "$VIDEO_PATH" ]; then
    echo "❌ 错误：净化后，在文件夹里找不到任何 mp4 视频文件！"
    exit 1
fi
VIDEO_NAME=$(basename "$VIDEO_PATH")
echo "🎯 锁定目标视频: $VIDEO_NAME"

echo " "
echo "⏳ [4/6] 正在给文件夹“称重”并匹配最完美的块大小..."
# 使用 du 命令获取文件夹总大小（单位：MB，去尾法整数）
SIZE_MB=$(du -sm "$FOLDER_PATH" | cut -f1)

# 根据你提供的黄金对照表，自动匹配对应的 -l 参数
if [ "$SIZE_MB" -lt 512 ]; then
    PIECE_L=18
elif [ "$SIZE_MB" -lt 1024 ]; then
    PIECE_L=19
elif [ "$SIZE_MB" -lt 2048 ]; then
    PIECE_L=20
elif [ "$SIZE_MB" -lt 4096 ]; then
    PIECE_L=21
elif [ "$SIZE_MB" -lt 8192 ]; then
    PIECE_L=22
elif [ "$SIZE_MB" -lt 16384 ]; then
    PIECE_L=23
else
    PIECE_L=24
fi
echo "📊 文件夹总大小: ${SIZE_MB} MB，已自动锁定参数: -l ${PIECE_L}"

TORRENT_FILE="$BASE_DIR/${FOLDER_NAME}.torrent"
INFO_FILE="$BASE_DIR/${FOLDER_NAME}_mediainfo.txt"

echo " "
echo "⏳ [5/6] 正在制作智能分块的纯净版种子..."
# 这里把原来的死参数 23 替换成了智能变量 $PIECE_L
mktorrent -v -p -l "$PIECE_L" -a "$TRACKER" -o "$TORRENT_FILE" "$FOLDER_PATH"
echo "✅ 种子制作完毕！"

echo " "
echo "⏳ [6/6] 正在抽取 3 张无损截图并提取参数..."
ffmpeg -ss 00:05:00 -i "$VIDEO_PATH" -q:v 2 -frames:v 1 "$BASE_DIR/${FOLDER_NAME}_5min.jpg" -y > /dev/null 2>&1
ffmpeg -ss 00:10:00 -i "$VIDEO_PATH" -q:v 2 -frames:v 1 "$BASE_DIR/${FOLDER_NAME}_10min.jpg" -y > /dev/null 2>&1
ffmpeg -ss 00:15:00 -i "$VIDEO_PATH" -q:v 2 -frames:v 1 "$BASE_DIR/${FOLDER_NAME}_15min.jpg" -y > /dev/null 2>&1
mediainfo "$VIDEO_PATH" > "$INFO_FILE"
echo "✅ 截图与参数文件生成完毕！"

echo " "
echo "======================================"
echo " 🎉 完美洗版发种！产出物都在 downloads 根目录下："
echo " 📦 智能种子：${FOLDER_NAME}.torrent"
echo " 🖼️ 截图文件：${FOLDER_NAME}_5min.jpg 等"
echo " 📄 参数文本：${FOLDER_NAME}_mediainfo.txt"
echo "======================================"