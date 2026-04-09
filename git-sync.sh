#!/bin/bash

# ==========================================
# 1. 自动化环境检查
# ==========================================
if ! command -v git >/dev/null 2>&1; then
    echo "正在安装 git..."
    apt-get update && apt-get install -y git
fi

AGSBX_DIR="$HOME/agsbx"
GL_CONF="$AGSBX_DIR/gl_token"
mkdir -p "$AGSBX_DIR"

# ==========================================
# 2. 智能交互判断
# ==========================================
if [ ! -f "$GL_CONF" ]; then
    echo "================================================="
    echo "       欢迎使用 Argosbx GitLab 自动配置"
    echo "================================================="
    # 这里就是你想要的“交互”
    read -p "请输入 GitLab Token: " token
    read -p "请输入 GitLab 用户名: " userid
    read -p "请输入项目名称: " project
    read -p "请输入分支(默认main): " branch
    branch=${branch:-"main"}

    # 保存配置到本地
    echo "$token" > "$AGSBX_DIR/gl_token"
    echo "$userid" > "$AGSBX_DIR/gl_user"
    echo "$project" > "$AGSBX_DIR/gl_project"
    echo "$branch" > "$AGSBX_DIR/gl_branch"
    
    echo -e "\n✅ 配置保存成功！准备执行首次同步..."
fi

# ==========================================
# 3. 自动执行安装与映射 (实现快捷命令)
# ==========================================
if [ ! -f "/usr/local/bin/git-sync" ]; then
    cp "$0" /usr/local/bin/git-sync 2>/dev/null || cat "$0" > /usr/local/bin/git-sync
    chmod +x /usr/local/bin/git-sync
    git config --global alias.sync "!/usr/local/bin/git-sync"
    echo "✅ 快捷命令 'git sync' 已安装。"
fi

# ==========================================
# 4. 核心同步跑起来
# ==========================================
echo "🚀 正在处理节点同步..."
# ... 这里接你之前的推送/合并代码逻辑 ...
# (执行推送命令)
echo "Done!"
