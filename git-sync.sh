#!/bin/bash

# ==========================================
# 颜色定义
# ==========================================
green="\033[32m"
red="\033[31m"
reset="\033[0m"

# ==========================================
# 自动安装依赖
# ==========================================
install_deps() {
    if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        echo -e "${green}正在安装必要组件...${reset}"
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y git curl
        elif command -v yum >/dev/null 2>&1; then
            yum install -y git curl
        fi
    fi
}

AGSBX_DIR="$HOME/agsbx"
JH_FILE="$AGSBX_DIR/jh.txt"
MERGE_LIST="$AGSBX_DIR/merge_list.txt"
mkdir -p "$AGSBX_DIR"
install_deps

# ==========================================
# 快捷命令安装逻辑 (执行一次，永久生效)
# ==========================================
setup_alias() {
    if [ ! -f "/usr/local/bin/git-sync" ]; then
        # 将当前运行的脚本内容写入系统目录
        curl -sL https://raw.githubusercontent.com/taizi8888/argOSBX/main/git-sync.sh -O /usr/local/bin/git-sync
        chmod +x /usr/local/bin/git-sync
        git config --global alias.sync "!/usr/local/bin/git-sync"
        echo -e "${green}✅ 快捷命令 'git sync' 已安装完成。${reset}"
    fi
}

# ==========================================
# 配置模块
# ==========================================
do_config() {
    echo -e "${green}=================================================${reset}"
    echo -e "${green}           GitLab 自动订阅配置向导                ${reset}"
    echo -e "${green}=================================================${reset}"
    read -p "1. 输入 GitLab User ID: " userid
    read -p "2. 输入访问令牌 (Token): " token
    read -p "3. 输入项目名 (Project): " project
    read -p "4. 输入分支名 (默认 main): " branch
    branch=${branch:-"main"}
    read -p "5. 输入邮箱 (随意): " email

    echo "$token" > "$AGSBX_DIR/gl_token"
    echo "$userid" > "$AGSBX_DIR/gl_user"
    echo "$project" > "$AGSBX_DIR/gl_project"
    echo "$branch" > "$AGSBX_DIR/gl_branch"
    echo "$email" > "$AGSBX_DIR/gl_email"
    echo -e "${green}✅ 配置已保存！${reset}"
}

# ==========================================
# 推送模块
# ==========================================
do_push() {
    if [ ! -f "$AGSBX_DIR/gl_token" ]; then
        echo -e "${red}❌ 未发现配置，请先进行配置！${reset}"
        do_config
    fi
    
    # 融合逻辑
    if [ -f "$MERGE_LIST" ]; then
        echo -e "${green}正在合并远程节点...${reset}"
        sed -i '$a\' "$JH_FILE" 2>/dev/null
        while IFS= read -r url || [ -n "$url" ]; do
            [ -n "$url" ] && echo -e "\n" >> "$JH_FILE" && curl -s -m 15 "$url" >> "$JH_FILE"
        done < "$MERGE_LIST"
    fi

    echo -e "${green}🚀 正在处理节点同步...${reset}"
    cd "$AGSBX_DIR" || exit
    token=$(cat gl_token); userid=$(cat gl_user); project=$(cat gl_project); branch=$(cat gl_branch); email=$(cat gl_email)
    
    rm -rf .git && git init >/dev/null 2>&1
    git config user.email "${email}" && git config user.name "${userid}"
    git checkout -b "${branch}" >/dev/null 2>&1
    git add jh.txt && git commit -m "Auto Update $(date)" >/dev/null 2>&1
    
    remote_url="https://oauth2:${token}@gitlab.com/${userid}/${project}.git"
    if git push --force "${remote_url}" HEAD:${branch} >/dev/null 2>&1; then
        echo -e "${green}✅ GitLab 推送成功！${reset}"
        echo -e "${green}订阅链接：https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/jh.txt/raw?ref=${branch}&private_token=${token}${reset}"
    else
        echo -e "${red}❌ 推送失败，请检查 Token 权限。${reset}"
    fi
}

# ==========================================
# 入口判断
# ==========================================
setup_alias

case "$1" in
    "config") do_config ;;
    "merge") 
        read -p "输入要融合的订阅链接: " m_url
        [ -n "$m_url" ] && echo "$m_url" >> "$MERGE_LIST" && echo "已添加" ;;
    *) do_push ;;
esac
