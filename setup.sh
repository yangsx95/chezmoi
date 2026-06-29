#!/bin/bash

# ============================================================
# chezmoi dotfiles 统一安装脚本
# 支持 macOS、Linux、WSL
# 可重复执行：首次初始化 或 后续更新配置
# ============================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

# Ensure tools installed into user-local paths are available in this run.
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

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

# WSL 额外提示
if [ "$OS" = "wsl" ]; then
    echo -e "${CYAN}检测到 WSL 环境。${NC}"
    echo -e "${YELLOW}  • 建议在 Windows 侧安装 VcXsrv/GWSL 以支持 X11 GUI${NC}"
    echo -e "${YELLOW}  • 将 ~/.wslconfig 手动复制到 Windows %USERPROFILE% 以启用 mirrored 网络模式${NC}"
fi

# ────────────────────────────────────────
# 函数：安装系统基础依赖
# ────────────────────────────────────────
install_system_packages() {
    echo -e "${YELLOW}检查系统基础依赖...${NC}"

    case $OS in
        "macos")
            if ! command -v brew &> /dev/null; then
                echo -e "${YELLOW}未检测到 Homebrew，请先安装 Homebrew 后继续。${NC}"
                return
            fi
            local brew_packages=(
                git
                curl
                zsh
                unzip
                zip
                jq
                ripgrep
                fd
                tree
                htop
                git-extras
            )
            echo -e "${CYAN}通过 Homebrew 安装/更新基础工具...${NC}"
            brew install "${brew_packages[@]}" || echo -e "${YELLOW}部分 Homebrew 包安装失败或已安装，继续执行。${NC}"
            ;;
        "linux"|"wsl")
            if ! command -v apt-get &> /dev/null; then
                echo -e "${YELLOW}当前 Linux 发行版未检测到 apt-get，跳过系统包自动安装。${NC}"
                return
            fi

            local apt_packages=(
                build-essential
                ca-certificates
                curl
                fd-find
                git
                git-extras
                htop
                jq
                libssl-dev
                openssl
                pkg-config
                python3-pygments
                ripgrep
                tree
                unzip
                wget
                zip
                zsh
            )

            echo -e "${CYAN}通过 apt 安装基础工具（需要 sudo）...${NC}"
            sudo apt-get update
            sudo apt-get install -y "${apt_packages[@]}"

            if command -v fdfind &> /dev/null && ! command -v fd &> /dev/null; then
                mkdir -p "$HOME/.local/bin"
                ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
            fi
            ;;
        *)
            echo -e "${YELLOW}未知系统类型，跳过系统包安装。${NC}"
            ;;
    esac
}

# ────────────────────────────────────────
# GitHub 仓库：DOTFILES_REPO_URL > GITHUB_TOKEN/GH_TOKEN > SSH
# ────────────────────────────────────────
SLUG="${DOTFILES_GITHUB_SLUG:-yangsx95/chezmoi}"
if [ -n "${DOTFILES_REPO_URL:-}" ]; then
    REPO_URL="$DOTFILES_REPO_URL"
elif [ -n "${GITHUB_TOKEN:-}" ] || [ -n "${GH_TOKEN:-}" ]; then
    TOKEN="${GITHUB_TOKEN:-$GH_TOKEN}"
    REPO_URL="https://${TOKEN}@github.com/${SLUG}.git"
else
    REPO_URL="git@github.com:${SLUG}.git"
    echo -e "${YELLOW}未设置 GITHUB_TOKEN：将使用 SSH ${REPO_URL}${NC}"
    # 检查 SSH 密钥是否存在，不存在则提示生成
    if [ ! -f "$HOME/.ssh/id_ed25519" ] && [ ! -f "$HOME/.ssh/id_rsa" ]; then
        echo -e "${YELLOW}未检测到 SSH 密钥，建议生成:${NC}"
        echo -e "${WHITE}  ssh-keygen -t ed25519 -C \"${GIT_AUTHOR_EMAIL:-your@email.com}\"${NC}"
        echo -e "${WHITE}  cat ~/.ssh/id_ed25519.pub  # 添加到 GitHub Settings > SSH Keys${NC}"
    fi
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
            echo -e "${CYAN}使用 curl 安装 chezmoi 到 ~/.local/bin...${NC}"
            mkdir -p "$HOME/.local/bin"
            curl -fsSL --max-time 60 get.chezmoi.io | sh -s -- -b "$HOME/.local/bin"
            echo -e "${GREEN}已将 chezmoi 安装到 $HOME/.local/bin/chezmoi${NC}"
            ;;
    esac

    echo -e "${GREEN}chezmoi 安装成功${NC}"
}

# ────────────────────────────────────────
# 函数：安装 oh-my-zsh 和外部插件
# ────────────────────────────────────────
install_zsh_stack() {
    echo -e "${YELLOW}检查 zsh / oh-my-zsh 配置...${NC}"

    if ! command -v zsh &> /dev/null; then
        echo -e "${YELLOW}zsh 未安装，跳过 oh-my-zsh 配置。${NC}"
        return
    fi

    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        echo -e "${CYAN}安装 oh-my-zsh...${NC}"
        local omz_installer
        omz_installer=$(mktemp)
        if curl -fsSL --max-time 60 https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$omz_installer"; then
            RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh "$omz_installer"
        else
            echo -e "${RED}oh-my-zsh 安装脚本下载失败，跳过。${NC}"
        fi
        rm -f "$omz_installer"
    else
        echo -e "${GREEN}oh-my-zsh 已安装，跳过。${NC}"
    fi

    local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    mkdir -p "$zsh_custom/plugins"

    install_zsh_plugin "zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions" "$zsh_custom/plugins/zsh-autosuggestions"
    install_zsh_plugin "zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting" "$zsh_custom/plugins/zsh-syntax-highlighting"

    set_default_shell_zsh
}

install_zsh_plugin() {
    local name="$1"
    local repo="$2"
    local dest="$3"

    if [ -d "$dest/.git" ]; then
        echo -e "${GREEN}${name} 已安装，跳过。${NC}"
        return
    fi

    echo -e "${CYAN}安装 zsh 插件: ${name}${NC}"
    if ! git clone --depth=1 "$repo" "$dest"; then
        echo -e "${YELLOW}${name} 安装失败，后续可手动重试。${NC}"
    fi
}

set_default_shell_zsh() {
    local zsh_path
    zsh_path="$(command -v zsh)"
    local current_shell
    current_shell="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)"

    if [ "$current_shell" = "$zsh_path" ]; then
        echo -e "${GREEN}默认 shell 已是 zsh。${NC}"
        return
    fi

    if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
        echo -e "${CYAN}将 ${zsh_path} 加入 /etc/shells（需要 sudo）...${NC}"
        echo "$zsh_path" | sudo tee -a /etc/shells > /dev/null
    fi

    echo -e "${CYAN}设置默认 shell 为 zsh（可能需要输入密码）...${NC}"
    if chsh -s "$zsh_path"; then
        echo -e "${GREEN}默认 shell 已设置为 zsh，新开终端后生效。${NC}"
    else
        echo -e "${YELLOW}自动切换默认 shell 失败，可手动执行: chsh -s ${zsh_path}${NC}"
    fi
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

    export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

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
                echo -e "${GREEN}Miniconda 已安装。建议执行: ${HOME}/miniconda3/bin/conda init zsh${NC}"
            fi
            ;;
        *)
            echo -e "${YELLOW}当前 OS=$OS，未配置自动安装 conda。${NC}"
            ;;
    esac
}

# ────────────────────────────────────────
# Clash 客户端（macOS：Homebrew；Linux/WSL：AppImage 或 DEB）
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
            local CLASH_REPO="clash-verge-rev/clash-verge-rev"
            local CLASH_VERSION
            CLASH_VERSION=$(curl -fsSL --max-time 15 "https://api.github.com/repos/${CLASH_REPO}/releases/latest" 2>/dev/null | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\(.*\)".*/\1/')

            if [ -z "$CLASH_VERSION" ]; then
                echo -e "${YELLOW}无法获取 Clash Verge Rev 最新版本，请手动安装: https://github.com/${CLASH_REPO}/releases${NC}"
                return
            fi

            echo -e "${CYAN}安装 Clash Verge Rev ${CLASH_VERSION} (Linux/WSL)...${NC}"

            # 移除 v 前缀
            local VER="${CLASH_VERSION#v}"

            # 优先尝试 DEB（Ubuntu/Debian/WSL 默认），否则 AppImage
            if command -v dpkg &> /dev/null; then
                local ARCH
                ARCH=$(dpkg --print-architecture)
                local DEB_URL="https://github.com/${CLASH_REPO}/releases/download/${CLASH_VERSION}/Clash.Verge_${VER}_${ARCH}.deb"
                local TMP_DEB=$(mktemp /tmp/clash-verge.XXXXXX.deb)

                echo -e "${CYAN}下载 ${DEB_URL} ...${NC}"
                if curl -fsSL --max-time 120 -o "$TMP_DEB" "$DEB_URL"; then
                    echo -e "${CYAN}安装 DEB 包 (需要 sudo)...${NC}"
                    if sudo dpkg -i "$TMP_DEB" 2>/dev/null; then
                        echo -e "${GREEN}Clash Verge Rev DEB 安装完成${NC}"
                    else
                        sudo apt-get install -f -y 2>/dev/null && sudo dpkg -i "$TMP_DEB" && echo -e "${GREEN}Clash Verge Rev DEB 安装完成（依赖已修复）${NC}"
                    fi
                else
                    echo -e "${YELLOW}DEB 下载失败，尝试 AppImage...${NC}"
                    _install_clash_appimage "$CLASH_REPO" "$CLASH_VERSION" "$VER"
                fi
                rm -f "$TMP_DEB"
            else
                _install_clash_appimage "$CLASH_REPO" "$CLASH_VERSION" "$VER"
            fi
            ;;
        *)
            ;;
    esac
}

_install_clash_appimage() {
    local repo="$1" version="$2" ver="$3"
    local ARCH
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
    esac

    local APPIMAGE_URL="https://github.com/${repo}/releases/download/${version}/Clash.Verge_${ver}_${ARCH}.AppImage"
    local INSTALL_DIR="${HOME}/.local/bin"
    local APPIMAGE_PATH="${INSTALL_DIR}/clash-verge-rev.AppImage"

    mkdir -p "$INSTALL_DIR"

    echo -e "${CYAN}下载 AppImage: ${APPIMAGE_URL} ...${NC}"
    if curl -fsSL --max-time 120 -o "$APPIMAGE_PATH" "$APPIMAGE_URL"; then
        chmod +x "$APPIMAGE_PATH"
        echo -e "${GREEN}Clash Verge Rev AppImage 已安装到 ${APPIMAGE_PATH}${NC}"
        echo -e "${YELLOW}  • 确保 \$HOME/.local/bin 在 PATH 中${NC}"
        echo -e "${YELLOW}  • WSL 用户需安装 VcXsrv/GWSL 以支持 GUI${NC}"
    else
        echo -e "${RED}AppImage 下载失败${NC}"
        echo -e "${YELLOW}请手动安装: https://github.com/${repo}/releases${NC}"
    fi
}

# ────────────────────────────────────────
# 主流程
# ────────────────────────────────────────
main() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}环境配置初始化/更新脚本开始执行${NC}"
    echo -e "${CYAN}========================================${NC}"

    # 1. 安装系统基础依赖
    install_system_packages

    # 2. 安装依赖工具
    install_chezmoi
    install_mise

    # 3. 安装 zsh / oh-my-zsh 体验
    install_zsh_stack

    # 4. 初始化或更新 chezmoi 配置
    init_or_update_chezmoi "$REPO_URL"

    # 5. 安装 mise 声明的工具
    install_mise_tools

    # 6. 安装 Miniconda / conda（可选跳过）
    install_conda

    # 7. Clash 客户端（可选跳过）
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
        "linux")
            echo -e "${YELLOW}执行: source ~/.bashrc 或 source ~/.zshrc${NC}"
            ;;
        "wsl")
            echo -e "${YELLOW}执行: source ~/.zshrc${NC}"
            echo -e "${YELLOW}WSL 提示：${NC}"
            echo -e "${WHITE}  • 将仓库中的 .wslconfig 复制到 Windows 用户目录以启用 mirrored 网络${NC}"
            echo -e "${WHITE}  • 推荐安装 Windows Terminal 作为 WSL 终端${NC}"
            ;;
        "macos")
            echo -e "${YELLOW}执行: source ~/.zshrc${NC}"
            ;;
    esac
}

# 执行主函数
main
