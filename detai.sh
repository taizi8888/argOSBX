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

# --- 节点进阶管理 (彻底修复参数传递逻辑) ---
manage_node() {
    echo "--- 节点进阶管理 ---"
    echo "1. 部署 Argo 节点 (默认部署)"
    echo "2. [list]  显示节点信息"
    echo "3. [rep]   重置变量组 (自定义协议)"
    echo "4. [res]   重启脚本"
    echo "5. [del]   卸载脚本"
    echo "6. [git]   配置 GitLab 订阅"
    echo "7. [merge] 配置节点融合"
    echo "------------------------------------------------"
    read -p "请选择编号或输入命令简写: " n_opt
    case $n_opt in
        1) bash <(curl -Ls https://raw.githubusercontent.com/taizi8888/argOSBX/main/argosbxj.sh) ;;
        2|list) bash <(curl -Ls https://raw.githubusercontent.com/taizi8888/argOSBX/main/argosbxj.sh) list ;;
        3|rep) bash <(curl -Ls https://raw.githubusercontent.com/taizi8888/argOSBX/main/argosbxj.sh) rep ;;
        4|res) bash <(curl -Ls https://raw.githubusercontent.com/taizi8888/argOSBX/main/argosbxj.sh) res ;;
        5|del) bash <(curl -Ls https://raw.githubusercontent.com/taizi8888/argOSBX/main/argosbxj.sh) del ;;
        6|git) bash <(curl -Ls https://raw.githubusercontent.com/taizi8888/argOSBX/main/argosbxj.sh) git ;;
        7|merge) bash <(curl -Ls https://raw.githubusercontent.com/taizi8888/argOSBX/main/argosbxj.sh) merge ;;
    esac
    read -p "按回车返回主菜单..."
}

# --- 主循环 ---
while true; do
    get_sys_info
    echo "  1. 核心系统优化 (含BBR/Swap/清理)"
    echo "  2. 站点反代管理 (一键自动 SSL)"
    echo "  3. PT 下载与制种 (qB部署/pt_make发种)"
    echo "  4. 节点进阶配置 (全参数引擎化)"
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
            [ "$p_opt" == "2" ] && bash <(curl -Ls https://raw.githubusercontent.com/taizi8888/argOSBX/main/pt_make.sh) ;;
        4) manage_node ;;
        5) bash <(curl -Ls https://raw.githubusercontent.com/taizi8888/argOSBX/main/git-sync.sh) ;;
        8) 
            # 主程序的更新依然保留 tr，防止本地 Windows 污染
            curl -Ls https://raw.githubusercontent.com/taizi8888/argOSBX/main/detai.sh | tr -d '\r' > /usr/local/bin/t
            chmod +x /usr/local/bin/t
            exec /usr/local/bin/t ;;
        0) clear; exit 0 ;;
        *) echo "无效输入"; sleep 1 ;;
    esac
done
