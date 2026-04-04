#!/bin/bash

# 统一环境配置脚本 - 自动初始化或更新 dotfile 和 mise 配置
# 支持 macOS、Linux、WSL
# 可重复执行，用于首次初始化或后续更新配置

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

# ────────────────────────────────────────
# 检测操作系统
# ────────────────────────────────────────
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [[ -f /proc/version ]] && grep -qi "microsoft\|wsl" /proc/version; then
            echo "wsl"
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

OS=$(detect_os)

if [ -z "$OS" ]; then
    echo -e "${RED}无法识别当前操作系统，脚本退出。${NC}"
    exit 1
fi

echo -e "${GREEN}检测到系统类型: $OS${NC}"

# ────────────────────────────────────────
# GitHub 仓库（含 token 示例，请替换为真实 token 或使用 SSH）
# ────────────────────────────────────────
GITHUB_TOKEN="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"   # ← 请必替换！
REPO_URL="https://${GITHUB_TOKEN}@github.com/yangsx95/dotfiles.git"

# ────────────────────────────────────────
# 函数：安装 chezmoi
# ────────────────────────────────────────
install_chezmoi() {
    echo -e "${YELLOW}检查 chezmoi 是否已安装...${NC}"

    if command -v chezmoi &> /dev/null; then
        echo -e "${GREEN}chezmoi 已安装，跳过安装步骤${NC}"
        return
    fi

    echo -e "${CYAN}正在安装 chezmoi ...${NC}"

    case $OS in
        "macos")
            echo -e "${CYAN}使用 brew 安装 chezmoi...${NC}"
            brew install chezmoi
            ;;
        "linux"|"wsl")
            echo -e "${CYAN}使用 curl 安装 chezmoi 到 /usr/local/bin...${NC}"
            curl -fsSL --max-time 60 get.chezmoi.io | sh -s -- -b /usr/local/bin
            echo -e "${GREEN}已将 chezmoi 安装到 /usr/local/bin/chezmoi${NC}"
            ;;
    esac

    echo -e "${GREEN}chezmoi 安装成功${NC}"
}

# ────────────────────────────────────────
# 函数：安装 mise
# ────────────────────────────────────────
install_mise() {
    echo -e "${YELLOW}检查 mise 是否已安装...${NC}"

    if command -v mise &> /dev/null; then
        echo -e "${GREEN}mise 已安装，跳过安装步骤${NC}"
        return
    fi

    echo -e "${CYAN}正在安装 mise ...${NC}"

    case $OS in
        "macos")
            echo -e "${CYAN}使用 brew 安装 mise...${NC}"
            brew install mise
            ;;
        "linux"|"wsl")
            echo -e "${CYAN}使用 curl 安装 mise...${NC}"
            curl https://mise.jdx.dev/install.sh | sh
            ;;
    esac

    echo -e "${GREEN}mise 安装成功${NC}"
}

# ────────────────────────────────────────
# 函数：初始化或更新 chezmoi
# ────────────────────────────────────────
init_or_update_chezmoi() {
    local repo_url=$1

    echo -e "${YELLOW}处理 chezmoi 配置...${NC}"

    # 确保 chezmoi 数据目录存在
    local chezmoi_data_dir="$HOME/.local/share/chezmoi"
    if [[ ! -d "$chezmoi_data_dir" ]]; then
        echo -e "${CYAN}创建 chezmoi 数据目录: $chezmoi_data_dir${NC}"
        mkdir -p "$chezmoi_data_dir"
    fi

    local source_path=""
    if source_path=$(chezmoi source-path 2>/dev/null); then
        :
    else
        # 通常代表尚未初始化
        source_path=""
    fi

    if [ -n "$source_path" ]; then
        echo -e "${CYAN}已找到 chezmoi 仓库，正在尝试更新...${NC}"

        if chezmoi update --force; then
            echo -e "${GREEN}chezmoi 更新完成${NC}"
        else
            echo -e "${RED}更新失败${NC}"
            echo -e "${YELLOW}可能是因为本地文件被修改，需要重新初始化配置${NC}"

            # 询问用户是否执行 init
            read -p "更新失败，是否强制重新初始化？(y/N): " confirm

            if [[ ! $confirm =~ ^[yY]$ ]]; then
                echo -e "${YELLOW}用户取消，跳过重新初始化${NC}"
                return
            fi

            echo -e "${CYAN}执行强制重新初始化...${NC}"
            if chezmoi init --apply --force "$repo_url"; then
                echo -e "${GREEN}强制重新初始化完成${NC}"
            else
                echo -e "${RED}强制重新初始化失败${NC}"
                exit 1
            fi
        fi
    else
        echo -e "${CYAN}未找到 chezmoi 配置，开始初始化...${NC}"

        if chezmoi init --apply "$repo_url"; then
            echo -e "${GREEN}chezmoi 初始化完成${NC}"
        else
            echo -e "${RED}chezmoi 初始化失败${NC}"
            exit 1
        fi
    fi
}

# ────────────────────────────────────────
# 函数：安装 mise 声明的工具
# ────────────────────────────────────────
install_mise_tools() {
    if ! command -v mise &> /dev/null; then
        echo -e "${YELLOW}mise 未安装，无法执行工具安装，跳过${NC}"
        return
    fi

    echo -e "${CYAN}执行 mise install （安装 .mise.toml / .tool-versions 中声明的工具）...${NC}"

    if mise install; then
        echo -e "${GREEN}mise 工具安装完成${NC}"
    else
        echo -e "${RED}mise install 失败${NC}"
        # 不退出，让后续步骤继续执行
    fi
}

# ────────────────────────────────────────
# 主流程
# ────────────────────────────────────────
main() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}环境配置初始化/更新脚本开始执行${NC}"
    echo -e "${CYAN}========================================${NC}"

    # 1. 安装依赖工具
    install_chezmoi
    install_mise

    # 2. 初始化或更新 chezmoi 配置
    init_or_update_chezmoi "$REPO_URL"

    # 3. 安装 mise 声明的工具
    install_mise_tools

    echo -e "${CYAN}========================================${NC}"
    echo -e "${GREEN}环境配置完成！${NC}"
    echo -e "${CYAN}========================================${NC}"

    echo -e "\n${CYAN}常用命令参考：${NC}"
    echo -e "${WHITE}  • 更新配置      : chezmoi update${NC}"
    echo -e "${WHITE}  • 编辑文件      : chezmoi edit ~/.bashrc${NC}"
    echo -e "${WHITE}  • 强制应用      : chezmoi apply -v${NC}"
    echo -e "${WHITE}  • 进入仓库目录  : cd \$(chezmoi source-path)${NC}"

    # 提示重新加载 shell 配置
    echo -e "\n${YELLOW}提示: 请重新加载 shell 配置或重新打开终端以应用所有更改${NC}"
    case $OS in
        "linux"|"wsl")
            echo -e "${YELLOW}执行: source ~/.bashrc${NC}"
            ;;
        "macos")
            echo -e "${YELLOW}执行: source ~/.zshrc${NC}"
            ;;
    esac
}

# 执行主函数
main
