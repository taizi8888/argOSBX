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
            if ask_confirm "确认添加 Swap 虚拟内存吗？"; then
                read -p "输入虚拟内存大小(MB): " swap_size
                fallocate -l ${swap_size}M /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
                echo '/swapfile none swap sw 0 0' >> /etc/fstab
                echo "Swap 添加成功！"
            fi ;;
        3) 
            if ask_confirm "确认安装 Docker 引擎吗？"; then
                curl -fsSL https://get.docker.com | bash
                systemctl enable docker && systemctl start docker
                echo "Docker 安装完毕！"
            fi ;;
        4) 
            if ask_confirm "确认清理系统垃圾吗？"; then
                apt autoremove -y && apt clean
                if command -v docker &> /dev/null; then docker system prune -a -f; fi
                echo "垃圾清理完成！"
            fi ;;
    esac
    read -p "按回车返回主菜单..."
}

# 提取出的复用函数：添加自动续签定时任务
add_ssl_cron() {
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -l 2>/dev/null; echo "0 2 * * * certbot renew --quiet --post-hook \"systemctl reload nginx\"") | crontab -
        echo "SSL 证书自动续签任务已添加 (每天凌晨2点后台静默检查)！"
    else
        echo "SSL 证书自动续签任务已存在，无需重复添加！"
    fi
}

manage_web() {
    echo "--- 站点与反代签名管理 ---"
    echo "1. 一键配置反代并自动申请 SSL (静默模式 + 自动续签)"
    echo "2. 仅单独申请 SSL 证书 (包含自动续签)"
    read -p "请选择: " w_opt
    if [ "$w_opt" == "1" ]; then
        if ! command -v nginx &> /dev/null; then apt update && apt install nginx -y; fi
        read -p "请输入域名: " dom
        read -p "请输入本地端口: " port
        
        cat > /etc/nginx/sites-available/$dom <<EOFSERVER
server {
    listen 80;
    server_name $dom;
    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        client_max_body_size 50000m;
    }
}
EOFSERVER
        ln -sf /etc/nginx/sites-available/$dom /etc/nginx/sites-enabled/
        systemctl restart nginx
        
        if ask_confirm "是否立即自动签发 SSL HTTPS 证书？"; then
            if ! command -v certbot &> /dev/null; then apt update && apt install certbot python3-certbot-nginx -y; fi
            echo "正在静默签发证书..."
            certbot --nginx -d $dom --non-interactive --agree-tos --register-unsafely-without-email
            add_ssl_cron
            echo "域名 $dom 的反代与 SSL 已全部自动完成！"
        fi

    elif [ "$w_opt" == "2" ]; then
        if ! command -v certbot &> /dev/null; then apt update && apt install certbot python3-certbot-nginx -y; fi
        read -p "请输入域名: " dom
        echo "正在静默签发证书..."
        certbot --nginx -d $dom --non-interactive --agree-tos --register-unsafely-without-email
        add_ssl_cron
        echo "域名 $dom 的 SSL 证书已申请完成！"
    fi
    read -p "按回车返回主菜单..."
}

manage_pt() {
    echo "--- PT 生产线全能管理 ---"
    echo "1. 查看容器状态 | 2. qB 日志 | 3. 一键部署 qB | 4. 洗版发种引擎"
    read -p "请选择: " pt_opt
    case $pt_opt in
        1) if command -v docker &> /dev/null; then docker ps -a; fi ;;
        2) docker logs -f --tail 50 qbittorrent-nox ;;
        3) 
            if ask_confirm "确认部署 qB 容器吗？"; then
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
                echo "部署成功！访问地址: http://${PUB_IP}:8080"
            fi ;;
        4)
            if ask_confirm "运行 pt_make.sh？"; then
                bash <(curl -sL https://raw.githubusercontent.com/taizi8888/argOSBX/main/pt_make.sh | tr -d '\r')
            fi ;;
    esac
    read -p "按回车返回主菜单..."
}

manage_node() {
    echo "--- 节点与科学上网管理 ---"
    echo "1. 部署 Argo 节点 | 2. WARP 管理"
    read -p "请选择: " n_opt
    case $n_opt in
        1) if ask_confirm "部署 Argo 节点？"; then bash <(curl -sL https://raw.githubusercontent.com/taizi8888/argOSBX/main/argosbxj.sh | tr -d '\r'); fi ;;
        2) if command -v warp-cli &> /dev/null; then warp-cli status; fi ;;
    esac
    read -p "按回车返回主菜单..."
}

while true; do
    get_sys_info
    echo "  1. 核心系统优化 (含BBR/Swap/清理)"
    echo "  2. 站点反代管理 (一键自动 SSL + 自动续签)"
    echo "  3. PT 下载与制种 (qB部署/pt_make发种)"
    echo "  4. 节点与科学上网 (Argo/WARP)"
    echo "  5. Git 自动化同步 (执行 git-sync.sh)"
    echo "------------------------------------------------"
    echo "  8. 云端在线更新   | 0. 退出"
    echo "================================================================"
    read -p "请输入指令: " choice

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
                curl -sL https://raw.githubusercontent.com/taizi8888/argOSBX/main/detai.sh | tr -d '\r' > /usr/local/bin/t
                chmod +x /usr/local/bin/t
                exec /usr/local/bin/t
            fi ;;
        0) clear; exit 0 ;;
        *) echo "无效输入"; sleep 1 ;;
    esac
done
