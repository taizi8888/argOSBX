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
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y git curl
        fi
    fi
}

# 基础变量
AGSBX_DIR="$HOME/agsbx"
JH_FILE="$AGSBX_DIR/jh.txt"
MERGE_LIST="$AGSBX_DIR/merge_list.txt"

mkdir -p "$AGSBX_DIR"
install_deps

# ==========================================
# 模块1：配置 GitLab 信息 (对应你的 gitlabsub)
# ==========================================
gitlabsub(){
    echo "================================================="
    echo "           GitLab 自动订阅配置向导"
    echo "================================================="
    echo "提示：多台服务器请填写相同的Token和项目名，但使用不同的分支名！"
    echo "-------------------------------------------------"
    read -p "输入登录邮箱 (随意填): " email
    read -p "输入访问令牌 (Access Token): " token
    read -p "输入用户名 (User ID): " userid
    read -p "输入项目名 (Project Name): " project
    read -p "输入分支名称 (主服务器填main, 从服务器填node2等): " gitlabml
    
    gitlabml=${gitlabml:-"main"}

    # 保存配置
    echo "$email" > "$AGSBX_DIR/gl_email"
    echo "$token" > "$AGSBX_DIR/gl_token"
    echo "$userid" > "$AGSBX_DIR/gl_user"
    echo "$project" > "$AGSBX_DIR/gl_project"
    echo "$gitlabml" > "$AGSBX_DIR/gl_branch"
    
    # 生成订阅链接预览
    sub_link="https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/jh.txt/raw?ref=${gitlabml}&private_token=${token}"
    echo "$sub_link" > "$AGSBX_DIR/jh_sub_gitlab.txt"
    
    echo -e "\n配置已保存！\n当前订阅链接: $sub_link"
    gitlabsubgo
}

# ==========================================
# 模块2：执行自动推送 (对应你的 gitlabsubgo)
# ==========================================
gitlabsubgo(){
    if [ -f "$AGSBX_DIR/gl_token" ]; then
        # 融合逻辑：推送前先检查是否有融合列表并合并
        if [ -f "$MERGE_LIST" ]; then
            echo "发现融合列表，正在合并远程节点..."
            sed -i '$a\' "$JH_FILE" 2>/dev/null
            while IFS= read -r remote_url || [ -n "$remote_url" ]; do
                if [ -n "$remote_url" ]; then
                    echo " -> 抓取: ${remote_url:0:50}..."
                    echo -e "\n" >> "$JH_FILE"
                    curl -s -m 15 "$remote_url" >> "$JH_FILE"
                fi
            done < "$MERGE_LIST"
        fi

        cd "$AGSBX_DIR" || return
        email=$(cat gl_email)
        token=$(cat gl_token)
        userid=$(cat gl_user)
        project=$(cat gl_project)
        branch=$(cat gl_branch)
        
        echo "正在推送到 GitLab (分支: $branch)..."

        rm -rf .git
        git init >/dev/null 2>&1
        git config user.email "${email}"
        git config user.name "${userid}"
        git checkout -b "${branch}" >/dev/null 2>&1
        git add jh.txt >/dev/null 2>&1
        git commit -m "Auto Update $(date '+%Y-%m-%d %H:%M:%S')" >/dev/null 2>&1

        remote_url="https://oauth2:${token}@gitlab.com/${userid}/${project}.git"
        
        if git push --force "${remote_url}" HEAD:${branch} >/dev/null 2>&1; then
            echo -e "\033[32mGitLab 推送成功！\033[0m"
            echo "订阅链接: $(cat "$AGSBX_DIR/jh_sub_gitlab.txt" 2>/dev/null)"
        else
            echo -e "\033[31mGitLab 推送失败！请检查 Token 权限或项目名。\033[0m"
        fi
    fi
}

# ==========================================
# 模块3：节点融合配置 (对应你的 configure_merge)
# ==========================================
configure_merge(){
    echo "================================================="
    echo "           多节点融合配置 (仅主服务器使用)"
    echo "================================================="
    if [ -f "$MERGE_LIST" ]; then
        echo "当前已添加的融合链接："
        cat -n "$MERGE_LIST"
        echo "-------------------------------------------------"
    fi
    echo "1. 添加新链接"
    echo "2. 清空列表"
    echo "0. 退出"
    read -p "请选择: " choice
    if [ "$choice" = "1" ]; then
        read -p "请输入链接: " merge_url
        [ -n "$merge_url" ] && echo "$merge_url" >> "$MERGE_LIST" && echo "添加成功！"
    elif [ "$choice" = "2" ]; then
        rm -f "$MERGE_LIST" && echo "列表已清空。"
    fi
}

# 指令识别
case "$1" in
    "git") gitlabsub ;;
    "merge") configure_merge ;;
    *) gitlabsubgo ;;
esac