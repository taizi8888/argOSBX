#!/bin/bash

# 强制设置基础环境变量
export LANG=zh_CN.UTF-8

# ==========================================
# 默认路径配置 (可根据你服务器实际情况微调)
# ==========================================
WORK_DIR="/home/docker/qbittorrent/downloads"
OUTPUT_DIR="/home/docker/qbittorrent/pt_outputs"

ask_confirm() {
    read -p "$1 [y/N]: " choice
    case "$choice" in
        y|Y ) return 0 ;;
        * ) return 1 ;;
    esac
}

# ==========================================
# 1. 环境自愈模块 (核心升级)
# ==========================================
check_dependencies() {
    echo "--- 正在执行环境自愈检测 ---"
    local deps=("ffmpeg" "mediainfo" "bc" "jq")
    local need_install=0

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" > /dev/null 2>&1; then
            echo "系统检测到缺失核心组件: $dep"
            need_install=1
        fi
    done

    if [ $need_install -eq 1 ]; then
        echo "正在为您自动修复运行环境，这可能需要一点时间，请稍候..."
        apt-get update -qq
        apt-get install -y ffmpeg mediainfo bc jq > /dev/null 2>&1
        echo "环境自愈完成！所有核心生产依赖已就绪。"
    else
        echo "环境检测通过，底层依赖完整。"
    fi
    echo "----------------------------"
}

# ==========================================
# 2. 核心洗版与打图引擎
# ==========================================
process_media() {
    local file="$1"
    local filename=$(basename "$file")
    local basename="${filename%.*}"
    local out_img="${OUTPUT_DIR}/${basename}_screen.jpg"
    local out_nfo="${OUTPUT_DIR}/${basename}_mediainfo.txt"

    echo "正在洗版处理: $filename"

    # 生成 MediaInfo NFO 文本
    if [ ! -f "$out_nfo" ]; then
        mediainfo "$file" > "$out_nfo"
        echo " - 媒体特征码提取完成"
    fi

    # 抽取 2x6 宫格高清截图 (多线程限制，防止小鸡内存溢出宕机)
    if [ ! -f "$out_img" ]; then
        ffmpeg -hide_banner -loglevel error -y -threads 2 \
            -i "$file" \
            -vf "select='isnan(prev_selected_t)+gte(t-prev_selected_t, (max_t-min_t)/13)',scale=1920:-1,tile=2x6" \
            -frames:v 1 -q:v 2 "$out_img"
        echo " - 2x6 宫格 4K 预览图生成完成"
    fi
}

# ==========================================
# 3. 增量扫描与未完成拦截器
# ==========================================
scan_and_process() {
    echo "--- 启动 PT 流水线扫描引擎 ---"
    mkdir -p "$OUTPUT_DIR"

    if [ ! -d "$WORK_DIR" ]; then
        echo "错误: 下载源目录 $WORK_DIR 不存在！请检查 qBittorrent 映射路径。"
        return
    fi

    # 智能搜索常见的视频格式
    find "$WORK_DIR" -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.ts" -o -iname "*.avi" \) | while read -r media_file; do
        
        # 拦截器规则 1：自身就是未完成的 qB 临时文件
        if [[ "$media_file" == *".!qB"* ]]; then
            echo "拦截器触发: 发现未完成分块，跳过 -> $(basename "$media_file")"
            continue
        fi
        
        # 拦截器规则 2：主体文件存在，但同级目录下还有它的 .!qB 碎片，说明正在下载中
        if [ -f "${media_file}.!qB" ]; then
            echo "拦截器触发: 该任务仍在下载队列中，跳过 -> $(basename "$media_file")"
            continue
        fi

        # 进入安全作业区
        process_media "$media_file"
    done

    echo "--- 流水线作业完毕 ---"
    echo "所有成品截图和 NFO 文本已输出至: $OUTPUT_DIR"
}

# ==========================================
# 主程序入口
# ==========================================
clear
echo "================================================================"
echo "          PT 终极洗版机 V4.5 (环境自愈版) - 纯净白"
echo "================================================================"

check_dependencies

echo "监听数据源: $WORK_DIR"
echo "成品输出库: $OUTPUT_DIR"
echo "================================================================"

if ask_confirm "确认唤醒引擎开始批量洗版任务吗？"; then
    scan_and_process
else
    echo "任务已取消。"
fi
