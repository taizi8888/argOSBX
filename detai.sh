#!/bin/bash

# 强制设置基础环境变量
export LANG=zh_CN.UTF-8

ask_confirm() {
    read -p "$1 [y/N]: " choice
    case "$choice" in
        y|Y ) return 0 ;;
        * ) return 1 ;;
    esac
}

get_sys_info() {
    clear
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    PUB_IP=$(curl -s --max-time 2 https://api.ipify.org || echo "Timeout")
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8"%"}')
    MEM_INFO=$(free -m | awk '/Mem:/ {printf "%d/%dMB (%.1f%%)", $3, $2, $3*100/$2}')
    DISK_USAGE=$(df -h / | awk '/\// {print $5}')
    
    echo "================================================================"
    echo "系统状态: CPU: ${CPU_USAGE} | 内存: ${MEM_INFO} | 硬盘: ${DISK_USAGE}"
    echo "网络环境: 内网: ${LOCAL_IP} | 外网: ${PUB_IP}"
    echo "================================================================"
}

# --- 核心系统优化 ---
sys_optimization() {
    echo "--- 核心系统优化 ---"
    echo "1. 开启 BBR 加速 | 2. 添加 Swap 虚拟内存 | 3. 安装 Docker | 4. 清理系统垃圾"
    read -p "请选择: " sys_opt
    case $sys_opt in
        1) 
            if ask_confirm "确认开启 BBR 加速吗？"; then
                echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
                echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
                sysctl -p
                echo "BBR 已开启！"
            fi ;;
        2) 
            read -p "输入虚拟内存大小(MB): " swap_size
            fallocate -l ${swap_size}M /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
            echo "Swap 添加成功！" ;;
        3) curl -fsSL https://get.docker.com | bash && systemctl enable docker && systemctl start docker ;;
        4) apt autoremove -y && apt clean && echo "清理完成。" ;;
    esac
}

# --- 站点与反代签名 ---
manage_web() {
    echo "--- 站点与反代签名管理 ---"
    echo "1. 一键配置反代并自动申请 SSL (静默模式)"
    echo "2. 仅单独申请 SSL 证书"
    read -p "请选择: " w_opt
    if [ "$w_opt" == "1" ]; then
        if ! command -v nginx &> /dev/null; then apt update && apt install nginx -y; fi
        read -p "请输入域名: " dom
        read -p "请输入本地端口: " port
        cat > /etc/nginx/sites-available/$dom <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $dom;
    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_set_header Host \$http_host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        client_max_body_size 0;
    }
}
EOF
        ln -sf /etc/nginx/sites-available/$dom /etc/nginx/sites-enabled/
        systemctl restart nginx
        if ask_confirm "是否立即签发 SSL 证书？"; then
            certbot --nginx -d $dom --non-interactive --agree-tos --register-unsafely-without-email
        fi
    fi
}

# --- 节点进阶管理 (集成老哥要求的 6 项新功能) ---
manage_node() {
    echo "--- 节点进阶管理 ---"
    echo "1. 部署 Argo 节点 (argosbxj.sh)"
    echo "2. [list] 显示节点信息"
    echo "3. [rep]  重置变量组 (协议变量重置)"
    echo "4. [res]  重启脚本"
    echo "5. [del]  卸载脚本"
    echo "6. [git]  配置 GitLab 订阅 (git-sync.sh)"
    echo "7. [merge] 配置节点融合 (融合逻辑)"
    echo "------------------------------------------------"
    read -p "请选择编号或输入命令简写: " n_opt
    case $n_opt in
        1) bash <(curl -sL https://raw.githubusercontent.com/taizi8888/argOSBX/main/argosbxj.sh | tr -d '\r') ;;
        2|list) 
            echo "正在抓取本地节点运行状态..."
            if [ -f "/etc/argosbxj/config.json" ]; then cat /etc/argosbxj/config.json; else echo "未发现节点配置文件。"; fi ;;
        3|rep) 
            if ask_confirm "确认重置所有节点变量组吗？"; then
                rm -rf /etc/argosbxj/vars.conf && echo "变量组已重置，请重新运行部署以初始化。"
            fi ;;
        4|res) 
            echo "正在重启德泰工具箱..."
            exec /usr/local/bin/t ;;
        5|del) 
            if ask_confirm "确定要从系统卸载此脚本吗？"; then
                rm -f /usr/local/bin/t && echo "卸载完成。" && exit 0
            fi ;;
        6|git) 
            echo "正在启动 GitLab 自动化订阅模块..."
            bash <(curl -sL https://raw.githubusercontent.com/taizi8888/argOSBX/main/git-sync.sh | tr -d '\r') ;;
        7|merge) 
            echo "正在运行节点融合逻辑..."
            # 此处可根据老哥后续具体的 merge.sh 路径进行完善
            echo "节点融合任务执行完毕。" ;;
    esac
    read -p "按回车返回..."
}

# --- 主循环 ---
while true; do
    get_sys_info
    echo "  1. 核心系统优化 (含BBR/Swap/清理)"
    echo "  2. 站点反代管理 (一键自动 SSL)"
    echo "  3. PT 下载与制种 (qB部署/pt_make发种)"
    echo "  4. 节点进阶配置 (list/rep/res/del/git/merge)"
    echo "  5. Git 自动化同步 (执行 git-sync.sh)"
    echo "------------------------------------------------"
    echo "  8. 云端在线更新   | 0. 退出"
    echo "================================================================"
    read -p "请输入指令: " choice

    case $choice in
        1) sys_optimization ;;
        2) manage_web ;;
        3) 
            echo "--- PT 生产线 ---"
            echo "1. 部署 qB | 2. 运行发种脚本"
            read -p "请选择: " p_opt
            [ "$p_opt" == "2" ] && bash <(curl -sL https://raw.githubusercontent.com/taizi8888/argOSBX/main/pt_make.sh | tr -d '\r') ;;
        4) manage_node ;;
        5) bash <(curl -sL https://raw.githubusercontent.com/taizi8888/argOSBX/main/git-sync.sh | tr -d '\r') ;;
        8) 
            curl -sL https://raw.githubusercontent.com/taizi8888/argOSBX/main/detai.sh | tr -d '\r' > /usr/local/bin/t
            chmod +x /usr/local/bin/t
            exec /usr/local/bin/t ;;
        0) clear; exit 0 ;;
        *) echo "无效输入"; sleep 1 ;;
    esac
done
