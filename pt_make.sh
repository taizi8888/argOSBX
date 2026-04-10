#!/bin/bash

# ==========================================
# 0. 首次运行初始化 (保留了之前的丝滑唤醒功能)
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
# 1. 核心运行逻辑：PT 洗版 + 首发流水线
# ==========================================

BASE_DIR="/home/docker/qbittorrent/downloads"
TRACKER="https://rousi.pro/tracker/808263a94ed47ca690395ca957b562e4/announce"

echo "======================================"
echo "    🚀 PT 纯净洗版 + 一键发种流水线    "
echo "======================================"

# 现在只需要输入文件夹名，剩下的全自动！
read -p "👉 请输入要处理的【文件夹名称】 (例如 savr-1022): " FOLDER_NAME

FOLDER_PATH="$BASE_DIR/$FOLDER_NAME"

# 安全检查
if [ ! -d "$FOLDER_PATH" ]; then
    echo "❌ 错误：找不到文件夹 $FOLDER_PATH ，请检查拼写！"
    exit 1
fi

echo " "
echo "⏳ [1/5] 正在执行“净网行动”：删除广告和垃圾文件..."
find "$FOLDER_PATH" -type f -name "*.url" -delete
find "$FOLDER_PATH" -type f -name "*.txt" -delete
# 核心杀招：自动删除小于 50MB 的小体积广告视频
find "$FOLDER_PATH" -type f -name "*.mp4" -size -50M -delete
echo "✅ 垃圾文件清理完毕！"

echo " "
echo "⏳ [2/5] 正在执行“去水印”：自动清理文件名广告前缀..."
for file in "$FOLDER_PATH"/*; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        # 如果文件名包含 @ 符号，则掐头去尾
        if [[ "$filename" == *"@"* ]]; then
            newname="${filename#*@}"
            mv "$file" "$FOLDER_PATH/$newname"
            echo "   🔄 重命名: $filename -> $newname"
        fi
    fi
done
echo "✅ 文件名净化完毕！"

echo " "
echo "⏳ [3/5] 正在智能定位主视频文件..."
# 自动找出文件夹里最大的 mp4 文件作为截图目标
VIDEO_PATH=$(find "$FOLDER_PATH" -maxdepth 1 -name "*.mp4" -type f -printf "%s\t%p\n" | sort -nr | head -n1 | cut -f2)

if [ -z "$VIDEO_PATH" ]; then
    echo "❌ 错误：净化后，在文件夹里找不到任何 mp4 视频文件！"
    exit 1
fi

VIDEO_NAME=$(basename "$VIDEO_PATH")
echo "🎯 锁定目标视频: $VIDEO_NAME (将对它进行截图和参数提取)"

TORRENT_FILE="$BASE_DIR/${FOLDER_NAME}.torrent"
INFO_FILE="$BASE_DIR/${FOLDER_NAME}_mediainfo.txt"

echo " "
echo "⏳ [4/5] 正在进入时间轴精准狙击截图 (5分/10分/15分)..."
ffmpeg -ss 00:05:00 -i "$VIDEO_PATH" -q:v 2 -frames:v 1 "$BASE_DIR/${FOLDER_NAME}_5min.jpg" -y > /dev/null 2>&1
ffmpeg -ss 00:10:00 -i "$VIDEO_PATH" -q:v 2 -frames:v 1 "$BASE_DIR/${FOLDER_NAME}_10min.jpg" -y > /dev/null 2>&1
ffmpeg -ss 00:15:00 -i "$VIDEO_PATH" -q:v 2 -frames:v 1 "$BASE_DIR/${FOLDER_NAME}_15min.jpg" -y > /dev/null 2>&1
echo "✅ 三张高质量缩略图抽取完毕！"

echo " "
echo "⏳ [5/5] 正在提取参数并制作最终纯净版种子..."
mediainfo "$VIDEO_PATH" > "$INFO_FILE"
mktorrent -v -p -l 23 -a "$TRACKER" -o "$TORRENT_FILE" "$FOLDER_PATH"
echo "✅ 种子制作完毕！"

echo " "
echo "======================================"
echo " 🎉 完美洗版发种！产出物都在 downloads 根目录下："
echo " 📦 纯净种子：${FOLDER_NAME}.torrent"
echo " 🖼️ 截图文件：${FOLDER_NAME}_5min.jpg 等"
echo " 📄 参数文本：${FOLDER_NAME}_mediainfo.txt"
echo "======================================"