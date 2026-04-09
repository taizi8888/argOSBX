#!/bin/bash

# 颜色定义
GREEN="\033[32m"
RED="\033[31m"
CYAN="\033[36m"
YELLOW="\033[33m"
RESET="\033[0m"

# 路径定义 (严格对齐官方脚本)
AGSBX_DIR="$HOME/agsbx"
JH_FILE="$AGSBX_DIR/jh.txt"
MERGE_LIST="$AGSBX_DIR/merge_list.txt"
mkdir -p "$AGSBX_DIR"

# ==========================================
# 1. 基础依赖检查
# ==========================================
install_deps() {
    if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        echo -e "${GREEN}正在安装必要依赖 (git/curl)...${RESET}"
        if command -v apk >/dev/null 2>&1; then apk update && apk add git curl >/dev/null 2>&1;
        elif command -v apt-get >/dev/null 2>&1; then apt-get update && apt-get install -y git curl >/dev/null 2>&1;
        elif command -v yum >/dev/null 2>&1; then yum install -y git curl >/dev/null 2>&1;
        elif command -v dnf >/dev/null 2>&1; then dnf install -y git curl >/dev/null 2>&1;
        fi
    fi
}
install_deps

# ==========================================
# 2. 极致快捷命令注册 (git sync / g / gg)
# ==========================================
if [ ! -f "/usr/local/bin/git-sync" ]; then
    cat "$0" > /usr/local/bin/git-sync
    chmod +x /usr/local/bin/git-sync
fi

if ! grep -q "alias g='/usr/local/bin/git-sync'" ~/.bashrc; then
    echo "alias g='/usr/local/bin/git-sync'" >> ~/.bashrc
    echo "alias gg='/usr/local/bin/git-sync push'" >> ~/.bashrc
    source ~/.bashrc 2>/dev/null
    echo -e "${GREEN}✅ 极致快捷命令已激活！日常修改敲 'g'，一键起飞敲 'gg'。${RESET}"
    echo -e "${YELLOW}⚠️ 提示：如果按 g 提示找不到命令，请手动执行一次: source ~/.bashrc${RESET}"
fi

# ==========================================
# 模块 A：配置 GitLab
# ==========================================
do_config() {
    echo -e "\n${GREEN}=================================================${RESET}"
    echo -e "${GREEN}           GitLab 自动订阅配置向导                ${RESET}"
    echo -e "${GREEN}=================================================${RESET}"
    echo "提示：多台服务器请填写相同的Token和项目名，但使用不同的分支名！"
    echo "-------------------------------------------------"
    read -p "输入登录邮箱 (随意填): " email
    read -p "输入访问令牌 (Access Token，必须带 write_repository 权限): " token
    read -p "输入用户名 (User ID): " userid
    read -p "输入项目名 (Project Name): " project
    read -p "输入分支名称 (主服务器填main, 从机填node2等): " branch
    branch=${branch:-"main"}

    echo "$email" > "$AGSBX_DIR/gl_email"
    echo "$token" > "$AGSBX_DIR/gl_token"
    echo "$userid" > "$AGSBX_DIR/gl_user"
    echo "$project" > "$AGSBX_DIR/gl_project"
    echo "$branch" > "$AGSBX_DIR/gl_branch"
    
    sub_link="https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/jh.txt/raw?ref=${branch}&private_token=${token}"
    echo "$sub_link" > "$AGSBX_DIR/jh_sub_gitlab.txt"
    echo -e "${GREEN}✅ 配置已保存！${RESET}"
}

# ==========================================
# 模块 B：节点融合配置
# ==========================================
do_merge_config() {
    echo -e "\n${YELLOW}=================================================${RESET}"
    echo -e "${YELLOW}           多节点融合配置 (仅主服务器使用)        ${RESET}"
    echo -e "${YELLOW}=================================================${RESET}"
    echo "请粘贴从服务器(如ARM机器)的 GitLab Raw 订阅链接。"
    echo "-------------------------------------------------"
    if [ -f "$MERGE_LIST" ]; then
        echo -e "${CYAN}当前已添加的融合链接：${RESET}"
        cat -n "$MERGE_LIST"
        echo "-------------------------------------------------"
    fi
    echo "1. 添加新链接"
    echo "2. 清空列表"
    echo "0. 返回菜单"
    read -p "请选择: " choice
    if [ "$choice" = "1" ]; then
        read -p "请输入链接: " m_url
        [ -n "$m_url" ] && echo "$m_url" >> "$MERGE_LIST" && echo -e "${GREEN}✅ 添加成功！${RESET}"
    elif [ "$choice" = "2" ]; then
        rm -f "$MERGE_LIST" && echo -e "${GREEN}✅ 列表已清空。${RESET}"
    fi
}

# ==========================================
# 模块 C：同步与推送
# ==========================================
do_push() {
    if [ ! -f "$AGSBX_DIR/gl_token" ]; then
        echo -e "${RED}❌ 未发现配置，请先在菜单中选择 1 进行配置！${RESET}"
        return
    fi
    if [ ! -f "$JH_FILE" ]; then
        echo -e "${RED}❌ 未发现节点文件 jh.txt，请先运行官方 Argosbx 脚本生成节点！${RESET}"
        return
    fi

    echo -e "\n${GREEN}🚀 正在执行节点融合与同步推送...${RESET}"

    # 融合逻辑
    if [ -f "$MERGE_LIST" ]; then
        echo "发现融合列表，正在合并远程节点..."
        sed -i '$a\' "$JH_FILE" 2>/dev/null
        while IFS= read -r url || [ -n "$url" ]; do
            if [ -n "$url" ]; then
                echo " -> 抓取: ${url:0:45}..."
                echo -e "\n" >> "$JH_FILE"
                curl -s -m 15 "$url" >> "$JH_FILE"
            fi
        done < "$MERGE_LIST"
        echo "✅ 融合完成。"
    fi

    # 推送逻辑
    cd "$AGSBX_DIR" || exit
    email=$(cat gl_email); token=$(cat gl_token); userid=$(cat gl_user); project=$(cat gl_project); branch=$(cat gl_branch)
    
    echo "正在推送到 GitLab (分支: $branch)..."
    rm -rf .git && git init >/dev/null 2>&1
    git config user.email "${email}" && git config user.name "${userid}"
    git checkout -b "${branch}" >/dev/null 2>&1
    git add jh.txt >/dev/null 2>&1
    git commit -m "Auto Update $(date '+%Y-%m-%d %H:%M:%S')" >/dev/null 2>&1

    remote_url="https://oauth2:${token}@gitlab.com/${userid}/${project}.git"
    
    if git push --force "${remote_url}" HEAD:${branch} >/dev/null 2>&1; then
        echo -e "\n${GREEN}=================================================${RESET}"
        echo -e "${GREEN}✅ GitLab 推送成功！节点已同步至云端。${RESET}"
        echo -e "你的专属订阅地址为："
        echo -e "${CYAN}$(cat jh_sub_gitlab.txt)${RESET}"
        echo -e "${GREEN}=================================================${RESET}"
    else
        echo -e "\n${RED}❌ 推送失败！请检查 Token 权限 (必须勾选 api 和 write_repository) 或项目名是否正确。${RESET}"
    fi
}

# ==========================================
# 主程序：交互式菜单
# ==========================================
if [ "$1" = "push" ]; then do_push; exit 0; fi

while true; do
    echo -e "\n${CYAN}=======================================${RESET}"
    echo -e "${CYAN}      Argosbx 官方脚本 - 融合Git伴侣      ${RESET}"
    echo -e "${CYAN}=======================================${RESET}"
    if [ -f "$AGSBX_DIR/gl_token" ]; then
        echo -e "当前状态: ${GREEN}已配置${RESET} (分支: $(cat "$AGSBX_DIR/gl_branch" 2>/dev/null))"
    else
        echo -e "当前状态: ${RED}未配置${RESET}"
    fi
    echo "1. 配置 GitLab 账户信息 (填入你的新Token)"
    echo "2. 配置 多节点融合 (添加从机链接)"
    echo "3. 执行 同步推送 (合并并上传)"
    echo "0. 退出"
    echo -e "${CYAN}---------------------------------------${RESET}"
    read -p "请输入数字选择操作 [0-3]: " choice
    
    case $choice in
        1) do_config ;;
        2) do_merge_config ;;
        3) do_push ; break ;;
        0) echo "已退出。" ; break ;;
        *) echo -e "${RED}输入无效，请重新输入。${RESET}" ;;
    esac
done
