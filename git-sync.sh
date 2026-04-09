#!/bin/bash

# ==========================================
# 自动安装依赖
# ==========================================
install_deps() {
    if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        echo "正在安装必要组件..."
        if command -v apk >/dev/null 2>&1; then
            apk update && apk add git curl
        elif command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y git curl
        elif command -v yum >/dev/null 2>&1; then
            yum install -y git curl
        fi
    fi
}

AGSBX_DIR="$HOME/agsbx"
JH_FILE="$AGSBX_DIR/jh.txt"
MERGE_LIST="$AGSBX_DIR/merge_list.txt"
install_deps

# ==========================================
# 核心逻辑：自动识别配置状态
# ==========================================

# 1. 检查是否已经配置过 GitLab
if [ ! -f "$AGSBX_DIR/gl_token" ]; then
    echo "================================================="
    echo "       检测到首次运行，进入 GitLab 配置向导"
    echo "================================================="
    read -p "输入登录邮箱: " email
    read -p "输入访问令牌 (Token): " token
    read -p "输入用户名 (User ID): " userid
    read -p "输入项目名 (Project Name): " project
    read -p "输入分支名 (主服务器填main): " gitlabml
    
    gitlabml=${gitlabml:-"main"}

    echo "$email" > "$AGSBX_DIR/gl_email"
    echo "$token" > "$AGSBX_DIR/gl_token"
    echo "$userid" > "$AGSBX_DIR/gl_user"
    echo "$project" > "$AGSBX_DIR/gl_project"
    echo "$gitlabml" > "$AGSBX_DIR/gl_branch"
    
    sub_link="https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/jh.txt/raw?ref=${gitlabml}&private_token=${token}"
    echo "$sub_link" > "$AGSBX_DIR/jh_sub_gitlab.txt"
    echo "配置已保存！"
fi

# 2. 如果带有 "merge" 参数，则进入融合链接添加界面
if [ "$1" = "merge" ]; then
    echo "请输入要融合的从服务器 GitLab Raw 订阅链接:"
    read merge_url
    [ -n "$merge_url" ] && echo "$merge_url" >> "$MERGE_LIST" && echo "添加成功！"
fi

# 3. 执行同步逻辑 (配置完或已有配置会自动走到这里)
if [ -f "$AGSBX_DIR/gl_token" ]; then
    # 融合处理
    if [ -f "$MERGE_LIST" ]; then
        echo "正在合并远程节点..."
        sed -i '$a\' "$JH_FILE" 2>/dev/null
        while IFS= read -r url || [ -n "$url" ]; do
            [ -n "$url" ] && echo -e "\n" >> "$JH_FILE" && curl -s -m 15 "$url" >> "$JH_FILE"
        done < "$MERGE_LIST"
    fi

    # 读取配置并推送
    cd "$AGSBX_DIR" || exit
    token=$(cat gl_token); userid=$(cat gl_user); project=$(cat gl_project); branch=$(cat gl_branch); email=$(cat gl_email)
    
    echo "正在推送到 GitLab (分支: $branch)..."
    rm -rf .git && git init >/dev/null 2>&1
    git config user.email "${email}" && git config user.name "${userid}"
    git checkout -b "${branch}" >/dev/null 2>&1
    git add jh.txt && git commit -m "Auto Update $(date)" >/dev/null 2>&1
    
    remote_url="https://oauth2:${token}@gitlab.com/${userid}/${project}.git"
    if git push --force "${remote_url}" HEAD:${branch} >/dev/null 2>&1; then
        echo -e "\033[32m推送成功！\033[0m"
        echo "订阅链接: $(cat jh_sub_gitlab.txt)"
    else
        echo -e "\033[31m推送失败！请检查 Token 或权限。\033[0m"
    fi
fi
