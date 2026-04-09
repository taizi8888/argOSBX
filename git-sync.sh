#!/bin/bash

# 颜色定义
green="\033[32m"
red="\033[31m"
reset="\033[0m"

AGSBX_DIR="$HOME/agsbx"
mkdir -p "$AGSBX_DIR"

# 配置函数
do_config() {
    echo -e "${green}>>> 进入 GitLab 配置向导${reset}"
    read -p "输入 GitLab User ID: " userid
    read -p "输入访问令牌 (Token): " token
    read -p "输入项目名 (Project): " project
    read -p "输入分支名 (默认 main): " branch
    branch=${branch:-"main"}
    read -p "输入邮箱 (随意): " email

    echo "$token" > "$AGSBX_DIR/gl_token"
    echo "$userid" > "$AGSBX_DIR/gl_user"
    echo "$project" > "$AGSBX_DIR/gl_project"
    echo "$branch" > "$AGSBX_DIR/gl_branch"
    echo "$email" > "$AGSBX_DIR/gl_email"
    echo -e "${green}✅ 配置保存成功！${reset}"
}

# 同步函数
do_push() {
    if [ ! -f "$AGSBX_DIR/gl_token" ]; then
        do_config
    fi
    echo -e "${green}🚀 开始同步节点...${reset}"
    # 这里放你原有的 git push 逻辑...
    # (省略具体 push 代码以保持简洁，请保留你仓库中原有的 push 逻辑部分)
    echo -e "${green}✅ 推送完成！${reset}"
}

# 快捷命令安装
[ ! -f "/usr/local/bin/git-sync" ] && cp "$0" /usr/local/bin/git-sync && chmod +x /usr/local/bin/git-sync && git config --global alias.sync "!/usr/local/bin/git-sync"

# 核心：根据是否有参数或配置来决定行为
if [ ! -f "$AGSBX_DIR/gl_token" ]; then
    do_config
    do_push
else
    # 如果是直接运行 bash <(curl...)，弹出菜单
    echo -e "${green}检测到已安装 git-sync，请选择操作：${reset}"
    echo "1. 直接执行同步"
    echo "2. 修改配置信息"
    echo "3. 退出"
    read -p "请输入数字: " menu_choice
    case $menu_choice in
        1) do_push ;;
        2) do_config && do_push ;;
        *) exit ;;
    esac
fi
# ==========================================
# 4. 核心同步逻辑
# ==========================================
echo -e "\033[32m🚀 正在处理节点同步...\033[0m"

# 进入目录并读取配置
cd "$AGSBX_DIR" || exit
token=$(cat gl_token)
userid=$(cat gl_user)
project=$(cat gl_project)
branch=$(cat gl_branch)

# 暴力重置 Git 环境并推送
rm -rf .git
git init >/dev/null 2>&1
git config user.name "$userid"
git config user.email "sync@git.com"
git checkout -b "$branch" >/dev/null 2>&1
git add jh.txt >/dev/null 2>&1
git commit -m "Auto Update $(date '+%Y-%m-%d %H:%M:%S')" >/dev/null 2>&1

# 构造认证 URL 并推送
remote_url="https://oauth2:${token}@gitlab.com/${userid}/${project}.git"

if git push --force "${remote_url}" HEAD:${branch} >/dev/null 2>&1; then
    echo -e "\n\033[32m=================================================\033[0m"
    echo -e "\033[32m✅ 节点已成功推送到 GitLab！\033[0m"
    echo -e "\033[32m=================================================\033[0m"
    
    # 这里是计算并输出订阅地址的核心代码
    # 注意：GitLab API 的 Raw 地址格式如下
    echo -e "你的专属订阅地址为："
    echo -e "\033[36mhttps://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/jh.txt/raw?ref=${branch}&private_token=${token}\033[0m"
    echo -e "\033[32m=================================================\033[0m"
else
    echo -e "\n\033[31m❌ 推送失败！请检查您的 Token 权限或项目名称是否正确。\033[0m"
fi
