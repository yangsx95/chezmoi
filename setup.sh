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
# GitHub 仓库：勿写死令牌。DOTFILES_REPO_URL > GITHUB_TOKEN/GH_TOKEN > SSH
# ────────────────────────────────────────
SLUG="${DOTFILES_GITHUB_SLUG:-yangsx95/chezmoi}"
if [ -n "${DOTFILES_REPO_URL:-}" ]; then
    REPO_URL="$DOTFILES_REPO_URL"
elif [ -n "${GITHUB_TOKEN:-}" ] || [ -n "${GH_TOKEN:-}" ]; then
    TOKEN="${GITHUB_TOKEN:-$GH_TOKEN}"
    REPO_URL="https://${TOKEN}@github.com/${SLUG}.git"
else
    REPO_URL="git@github.com:${SLUG}.git"
    echo -e "${YELLOW}未设置 GITHUB_TOKEN：将使用 SSH ${REPO_URL}（请确保已配置 ssh.github.com 密钥）${NC}"
fi

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
# 安装 Conda（默认 Miniconda；完整版可设 DOTFILES_CONDA_FULL=1 使用 Anaconda3）
# 跳过：DOTFILES_SKIP_CONDA=1
# ────────────────────────────────────────
install_conda() {
    if [ "${DOTFILES_SKIP_CONDA:-}" = "1" ]; then
        echo -e "${YELLOW}已设置 DOTFILES_SKIP_CONDA=1，跳过 conda 安装。${NC}"
        return
    fi
    if command -v conda &> /dev/null; then
        echo -e "${GREEN}conda 已在 PATH 中，跳过安装。${NC}"
        return
    fi

    case "$OS" in
        macos)
            if ! command -v brew &> /dev/null; then
                echo -e "${YELLOW}未检测到 Homebrew，请手动安装: brew install --cask miniconda${NC}"
                return
            fi
            echo -e "${CYAN}通过 Homebrew 安装 miniconda ...${NC}"
            if brew install --cask miniconda; then
                echo -e "${GREEN}miniconda 安装完成。新开终端后执行: conda init zsh${NC}"
            else
                echo -e "${RED}brew 安装 miniconda 失败${NC}"
            fi
            ;;
        linux|wsl)
            if [ "${DOTFILES_CONDA_FULL:-}" = "1" ]; then
                echo -e "${YELLOW}完整 Anaconda 请从官网下载安装；此处仅支持 Miniconda 静默安装到 ~/miniconda3${NC}"
            fi
            ARCH=$(uname -m)
            case "$ARCH" in
                x86_64)  MINI_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh" ;;
                aarch64) MINI_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh" ;;
                *)
                    echo -e "${RED}不支持的架构: $ARCH${NC}"
                    return 1
                    ;;
            esac
            TMP=$(mktemp)
            echo -e "${CYAN}下载 Miniconda 安装脚本 ...${NC}"
            if ! curl -fsSL "$MINI_URL" -o "$TMP"; then
                echo -e "${RED}下载失败${NC}"
                rm -f "$TMP"
                return 1
            fi
            echo -e "${CYAN}静默安装到 ${HOME}/miniconda3 ...${NC}"
            bash "$TMP" -b -p "${HOME}/miniconda3"
            rm -f "$TMP"
            # shellcheck disable=SC1091
            if [ -f "${HOME}/miniconda3/bin/conda" ]; then
                echo -e "${GREEN}Miniconda 已安装。请将 ${HOME}/miniconda3/bin 加入 PATH，并执行: ${HOME}/miniconda3/bin/conda init bash${NC}"
            fi
            ;;
        *)
            echo -e "${YELLOW}当前 OS=$OS，未配置自动安装 conda。${NC}"
            ;;
    esac
}

# ────────────────────────────────────────
# Clash 图形客户端（macOS：Homebrew；Linux：仅提示）
# 跳过：DOTFILES_SKIP_CLASH=1
# ────────────────────────────────────────
install_clash() {
    if [ "${DOTFILES_SKIP_CLASH:-}" = "1" ]; then
        echo -e "${YELLOW}已设置 DOTFILES_SKIP_CLASH=1，跳过 Clash 安装。${NC}"
        return
    fi
    case "$OS" in
        macos)
            if ! command -v brew &> /dev/null; then
                echo -e "${YELLOW}无 Homebrew，跳过。可手动: brew install --cask clash-verge-rev${NC}"
                return
            fi
            echo -e "${CYAN}安装 Clash Verge Rev (macOS)...${NC}"
            brew install --cask clash-verge-rev || echo -e "${YELLOW}brew 安装失败或已安装${NC}"
            ;;
        linux|wsl)
            echo -e "${YELLOW}Linux/WSL 请自行安装 Clash / Mihomo / Clash Verge Rev，见: https://github.com/clash-verge-rev/clash-verge-rev${NC}"
            ;;
        *)
            ;;
    esac
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

    # 4. 安装 Miniconda / conda（可选跳过）
    install_conda

    # 5. Clash 客户端（可选跳过）
    install_clash

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
