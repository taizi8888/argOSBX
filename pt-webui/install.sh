cat << 'EOF' > ~/argOSBX/pt-webui/install.sh
#!/bin/bash
# 描述: ArgOSBX 分布式集群节点 - 全自动部署脚本 (终极双子星版)

set -e
echo -e "\033[1;36m=====================================================\033[0m"
echo -e "\033[1;33m 🚀 ArgOSBX 歼星舰节点 - 自动化集群并网部署 \033[0m"
echo -e "\033[1;36m=====================================================\033[0m"

# 1. 砸穿 8080 防火墙
echo -e "\033[1;32m [1/5] 正在暴力砸穿 8080 端口物理防火墙...\033[0m"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null 2>&1
apt-get install -y iptables-persistent git curl wget >/dev/null 2>&1
iptables -I INPUT -p tcp --dport 8080 -j ACCEPT 2>/dev/null || true
netfilter-persistent save >/dev/null 2>&1 || true

# 2. Docker 引擎自动化部署
if ! command -v docker >/dev/null 2>&1; then
    echo -e "\033[1;32m [2/5] 正在安装 Docker 级微服务引擎...\033[0m"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh >/dev/null 2>&1
    systemctl enable --now docker
else
    echo -e "\033[1;32m [2/5] Docker 引擎已就绪，跳过安装。\033[0m"
fi

# 3. 拉取星舰图纸
echo -e "\033[1;32m [3/5] 正在从云端拉取 shdetai 集群分支代码...\033[0m"
mkdir -p ~/argosbx-web
cd ~/argosbx-web
rm -rf argOSBX
git clone -b shdetai https://github.com/taizi8888/argOSBX.git
cd argOSBX/pt-webui

# 4. 智适应修改下载目录挂载
echo -e "\033[1;32m [4/5] 正在执行无损级物理路径桥接...\033[0m"
REAL_DOWNLOAD_DIR="/home/docker/qbittorrent/downloads"
mkdir -p "$REAL_DOWNLOAD_DIR"

if [ -f "docker-compose.yml" ]; then
    sed -i "s|.*:/downloads|      - ${REAL_DOWNLOAD_DIR}:/downloads|g" docker-compose.yml
else
    echo -e "\033[1;31m ⚠️ 警告：仓库中未找到 docker-compose.yml！请检查代码！\033[0m"
    exit 1
fi

# 5. 战区环境物理嗅探与点火 (核心进化点)
echo -e "\033[1;32m [5/5] 正在进行战区物理特征嗅探...\033[0m"
if [ -d "/vol3/1000/downloads" ] || [ -d "/home/taizi8888" ]; then
    echo -e "\033[1;33m 🎯 侦测结果：[飞牛 NAS 中枢]，激活 feiniu 档案！\033[0m"
    export COMPOSE_PROFILES=feiniu
else
    echo -e "\033[1;33m 🎯 侦测结果：[甲骨文 强袭节点]，激活 oracle 档案！\033[0m"
    export COMPOSE_PROFILES=oracle
fi

echo -e "\033[1;33m ⏳ 正在进行容器重铸与点火，请稍候 (约 1-2 分钟)...\033[0m"
systemctl restart docker
docker compose up -d --build

# 播报
PUBLIC_IP=$(curl -s ifconfig.me || echo "你的主机IP")
echo -e "\033[1;36m=====================================================\033[0m"
echo -e "\033[1;32m 🎉 节点并网成功！分布式集群已扩容！ \033[0m"
echo -e "\033[1;33m 👉 WebUI 访问: http://${PUBLIC_IP}:8080 \033[0m"
echo -e "\033[1;36m=====================================================\033[0m"
EOF
chmod +x ~/argOSBX/pt-webui/install.sh
