#!/bin/bash

# ==========================================
# 颜色与全局变量 (最原生的 Bash 变色逻辑)
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

ask_confirm() {
    read -p "$(echo -e "${YELLOW}$1 [y/N]: ${NC}")" choice
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
    
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${YELLOW}系统状态:${NC} CPU: ${CPU_USAGE} | 内存: ${MEM_INFO} | 硬盘: ${DISK_USAGE}"
    echo -e "${YELLOW}网络环境:${NC} 内网: ${LOCAL_IP} | 外网: ${PUB_IP}"
    echo -e "${CYAN}================================================================${NC}"
}

sys_optimization() {
    echo -e "${PURPLE}--- 🚀 核心系统优化 ---${NC}"
    echo -e "1. 开启 BBR 加速 | 2. 添加 Swap 虚拟内存 | 3. 安装 Docker | 4. 清理系统垃圾"
    read -p "👉 请选择: " sys_opt
    case $sys_opt in
        1) 
            if ask_confirm "确认开启 BBR 加速吗？"; then
                echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
                echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
                sysctl -p
                echo -e "${GREEN}✅ BBR 已开启！${NC}"
            fi ;;
        2) 
            if ask_confirm "确认添加 Swap 虚拟内存吗？"; then
                read -p "输入虚拟内存大小(MB): " swap_size
                fallocate -l ${swap_size}M /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
                echo '/swapfile none swap sw 0 0' >> /etc/fstab
                echo -e "${GREEN}✅ Swap 添加成功！${NC}"
            fi ;;
        3) 
            if ask_confirm "确认安装 Docker 引擎吗？"; then
                curl -fsSL https://get.docker.com | bash
                systemctl enable docker && systemctl start docker
                echo -e "${GREEN}✅ Docker 安装完毕！${NC}"
            fi ;;
        4) 
            if ask_confirm "确认清理系统无用包和 Docker 垃圾吗？"; then
                apt autoremove -y && apt clean
                if command -v docker &> /dev/null; then docker system prune -a -f; fi
                echo -e "${GREEN}✅ 垃圾清理完成！${NC}"
            fi ;;
    esac
    read -p "按回车返回主菜单..."
}

manage_web() {
    echo -e "${YELLOW}--- 🌐 站点与反代管理 ---${NC}"
    echo -e "1. 绑定域名反代 (配Nginx) | 2. 申请 SSL 证书"
    read -p "👉 请选择: " w_opt
    if [ "$w_opt" == "1" ]; then
        if ! command -v nginx &> /dev/null; then apt update && apt install nginx -y; fi
        read -p "域名: " dom && read -p "本地端口: " port
        cat > /etc/nginx/sites-available/$dom <<EOFSERVER
server { listen 80; server_name $dom; location / { proxy_pass http://127.0.0.1:$port; client_max_body_size 50000m; } }
EOFSERVER
        ln -sf /etc/nginx/sites-available/$dom /etc/nginx/sites-enabled/ && systemctl restart nginx
        echo -e "${GREEN}✅ 域名绑定成功！${NC}"
    elif [ "$w_opt" == "2" ]; then
        if ! command -v certbot &> /dev/null; then apt update && apt install certbot python3-certbot-nginx -y; fi
        read -p "域名: " dom && certbot --nginx -d $dom
    fi
    read -p "按回车返回主菜单..."
}

manage_pt() {
    echo -e "${BLUE}--- 🎬 PT 生产线全能管理 ---${NC}"
    echo -e "1. 查看容器状态 | 2. qB 日志 | 3. 一键部署 qB | 4. 🚀 洗版发种引擎 (pt_make.sh)"
    read -p "👉 请选择: " pt_opt
    case $pt_opt in
        1) if command -v docker &> /dev/null; then docker ps -a; fi ;;
        2) docker logs -f --tail 50 qbittorrent-nox ;;
        3) 
            if ask_confirm "确认部署 qBittorrent 容器吗？"; then
                mkdir -p /home/docker/qbittorrent/{config,downloads}
                cat > /home/docker/qbittorrent/docker-compose.yml <<EOFQBIT
version: "3"
services:
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent-nox
    environment:
      - PUID=0
      - PGID=0
      - TZ=Asia/Shanghai
      - WEBUI_PORT=8080
    volumes:
      - /home/docker/qbittorrent/config:/config
      - /home/docker/qbittorrent/downloads:/downloads
    ports:
      - 6881:6881
      - 6881:6881/udp
      - 8080:8080
    restart: always
EOFQBIT
                cd /home/docker/qbittorrent && docker compose up -d
                echo -e "${GREEN}✅ 部署成功！访问地址: http://${PUB_IP}:8080${NC}"
            fi ;;
        4)
            if ask_confirm "确认拉取并运行 pt_make.sh？"; then
                # 加入了 tr -d '\r' 过滤
                bash <(curl -sL https://raw.githubusercontent.com/taizi8888/argOSBX/main/pt_make.sh | tr -d '\r')
            fi ;;
    esac
    read -p "按回车返回主菜单..."
}

manage_node() {
    echo -e "${CYAN}--- ✈️ 节点与科学上网管理 ---${NC}"
    echo -e "1. 🚀 部署德泰专属 Argo (argosbxj.sh) | 2. WARP 管理"
    read -p "👉 请选择: " n_opt
    case $n_opt in
        1) if ask_confirm "部署 Argo 节点？"; then bash <(curl -sL https://raw.githubusercontent.com/taizi8888/argOSBX/main/argosbxj.sh | tr -d '\r'); fi ;;
        2) if command -v warp-cli &> /dev/null; then warp-cli status; fi ;;
    esac
    read -p "按回车返回主菜单..."
}

while true; do
    get_sys_info
    echo -e "  ${GREEN}1.${NC} 🚀 核心系统优化 ${YELLOW}(含BBR/Swap/清理)${NC}"
    echo -e "  ${GREEN}2.${NC} 🌐 站点反代管理 ${YELLOW}(域名绑定/SSL证书)${NC}"
    echo -e "  ${GREEN}3.${NC} 🎬 PT 下载与制种 ${YELLOW}(qB部署/pt_make发种)${NC}"
    echo -e "  ${GREEN}4.${NC} ✈️ 节点与科学上网 ${YELLOW}(德泰专属 Argo/WARP)${NC}"
    echo -e "  ${GREEN}5.${NC} 🐙 Git 自动化同步 ${YELLOW}(执行 git-sync.sh)${NC}"
    echo -e "  ${CYAN}------------------------------------------------${NC}"
    echo -e "  ${GREEN}8.${NC} 🔄 云端在线更新   | ${RED}0.${NC} 退出"
    echo -e "${CYAN}================================================================${NC}"
    read -p "👉 请输入指令: " choice

    case $choice in
        1) sys_optimization ;;
        2) manage_web ;;
        3) manage_pt ;;
        4) manage_node ;;
        5) 
            if ask_confirm "执行 Git 同步？"; then bash <(curl -sL https://raw.githubusercontent.com/taizi8888/argOSBX/main/git-sync.sh | tr -d '\r'); fi
            read -p "按回车返回..." ;;
        8) 
            if ask_confirm "拉取云端最新版覆盖？"; then
                # 在线更新时，自动粉碎回车符
                curl -sL https://raw.githubusercontent.com/taizi8888/argOSBX/main/detai.sh | tr -d '\r' > /usr/local/bin/t
                chmod +x /usr/local/bin/t
                exec /usr/local/bin/t
            fi ;;
        0) clear; exit 0 ;;
        *) echo "无效输入"; sleep 1 ;;
    esac
done