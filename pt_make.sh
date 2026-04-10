#!/bin/bash

# ==========================================
# 0. 首次运行初始化：自动注入全局快捷指令 'p'
# ==========================================
# 自动获取你下载本脚本时的真实完整路径，防止路径写死报错
SCRIPT_PATH=$(readlink -f "$0") 
BASHRC="$HOME/.bashrc"

# 检查 .bashrc 中是否已经存在这个快捷指令
if ! grep -q "alias p='$SCRIPT_PATH'" "$BASHRC"; then
    echo "======================================"
    echo " ✨ 检测到首次运行，正在执行初始化..."
    echo " ⚙️ 正在将本脚本注册为系统快捷指令 'p'..."
    echo "alias p='$SCRIPT_PATH'" >> "$BASHRC"
    echo " ✅ 快捷指令写入成功！"
    echo " 🔄 正在自动刷新系统环境，请稍候..."
    echo "======================================"
    sleep 2
    # 核心魔法：重新加载当前终端，让快捷键瞬间生效
    exec bash
fi

# ==========================================
# 1. 核心运行逻辑：PT 首发一条龙流水线
# ==========================================

# --- 基础配置（如果以后换了站点，改这里的 Tracker 即可） ---
BASE_DIR="/home/docker/qbittorrent/downloads"
TRACKER="https://rousi.pro/tracker/808263a94ed47ca690395ca957b562e4/announce"

echo "======================================"
echo "      🚀 PT 首发一条龙全自动脚本      "
echo "======================================"

# 询问用户输入
read -p "👉 请输入要制作种子的【文件夹名称】 (例如 mdvr-415): " FOLDER_NAME
read -p "👉 请输入该文件夹内的【视频文件全名】 (例如 mdvr00415_1_8k.mp4): " VIDEO_NAME

# 拼凑完整路径
FOLDER_PATH="$BASE_DIR/$FOLDER_NAME"
VIDEO_PATH="$FOLDER_PATH/$VIDEO_NAME"
TORRENT_FILE="$BASE_DIR/${FOLDER_NAME}.torrent"
INFO_FILE="$BASE_DIR/${FOLDER_NAME}_mediainfo.txt"

# 安全检查：防止手滑拼错名字
if [ ! -d "$FOLDER_PATH" ]; then
    echo "❌ 错误：找不到文件夹 $FOLDER_PATH ，请检查拼写！"
    exit 1
fi
if [ ! -f "$VIDEO_PATH" ]; then
    echo "❌ 错误：找不到视频文件 $VIDEO_PATH ，请检查拼写！"
    exit 1
fi

echo " "
echo "⏳ [1/3] 正在全速计算 Hash 制作种子..."
mktorrent -v -p -l 23 -a "$TRACKER" -o "$TORRENT_FILE" "$FOLDER_PATH"
echo "✅ 种子制作完成！"

echo " "
echo "⏳ [2/3] 正在进入时间轴精准狙击截图 (5分/10分/15分)..."
# -y 参数代表无声静默覆盖同名文件，避免卡住
ffmpeg -ss 00:05:00 -i "$VIDEO_PATH" -q:v 2 -frames:v 1 "$BASE_DIR/${FOLDER_NAME}_5min.jpg" -y > /dev/null 2>&1
ffmpeg -ss 00:10:00 -i "$VIDEO_PATH" -q:v 2 -frames:v 1 "$BASE_DIR/${FOLDER_NAME}_10min.jpg" -y > /dev/null 2>&1
ffmpeg -ss 00:15:00 -i "$VIDEO_PATH" -q:v 2 -frames:v 1 "$BASE_DIR/${FOLDER_NAME}_15min.jpg" -y > /dev/null 2>&1
echo "✅ 三张高质量缩略图抽取完毕！"

echo " "
echo "⏳ [3/3] 正在提取视频底层 Mediainfo 参数..."
mediainfo "$VIDEO_PATH" > "$INFO_FILE"
echo "✅ 参数提取完毕并已保存为纯文本文件！"

echo " "
echo "======================================"
echo " 🎉 全部任务圆满完成！产出物都在 downloads 根目录下："
echo " 📦 种子文件：${FOLDER_NAME}.torrent"
echo " 🖼️ 截图文件：${FOLDER_NAME}_5min.jpg 等"
echo " 📄 参数文本：${FOLDER_NAME}_mediainfo.txt"
echo "======================================"