#!/bin/bash

# ============================================================
# chezmoi dotfiles 统一安装脚本
# 支持 macOS、Linux、WSL
# 可重复执行：首次初始化 或 后续更新配置
# ============================================================

set -e
set -o pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo -e "${RED}请不要用 sudo/root 运行整个脚本。${NC}"
    echo -e "${YELLOW}chezmoi 会使用当前用户的 HOME；root 运行会写入 /root/.local/share/chezmoi。${NC}"
    if [ -n "${SUDO_USER:-}" ]; then
        echo -e "${CYAN}请改用普通用户执行: sudo -u ${SUDO_USER} -H bash setup.sh${NC}"
    else
        echo -e "${CYAN}请切换到你的普通用户后执行: bash setup.sh${NC}"
    fi
    exit 1
fi

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

if [ -z "$OS" ] || [ "$OS" = unknown ]; then
    echo -e "${RED}无法识别当前操作系统，脚本退出。${NC}"
    exit 1
fi

echo -e "${GREEN}检测到系统类型: $OS${NC}"

if [ "$OS" = "wsl" ]; then
    echo -e "${CYAN}检测到 WSL 环境。${NC}"
fi

# ────────────────────────────────────────
# 函数：配置 WSL
# ────────────────────────────────────────
merge_wsl_config() {
    local source_file=$1
    local output_file=$2

    awk -v default_user="$USER" '
        function append_missing(section) {
            if (section == "[boot]" && !has_systemd) {
                print "systemd=true"
                has_systemd = 1
            }
            if (section == "[user]" && !has_default_user) {
                print "default=" default_user
                has_default_user = 1
            }
            if (section == "[interop]" && !has_append_windows_path) {
                print "appendWindowsPath=false"
                has_append_windows_path = 1
            }
        }

        /^\[[^]]+\][[:space:]]*$/ {
            append_missing(section)
            section = $0
            if (section == "[boot]") has_boot = 1
            if (section == "[user]") has_user = 1
            if (section == "[interop]") has_interop = 1
            print
            next
        }
        section == "[boot]" && /^[[:space:]]*systemd[[:space:]]*=/ {
            if (!has_systemd) print "systemd=true"
            has_systemd = 1
            next
        }
        section == "[user]" && /^[[:space:]]*default[[:space:]]*=/ {
            if (!has_default_user) print "default=" default_user
            has_default_user = 1
            next
        }
        section == "[interop]" && /^[[:space:]]*appendWindowsPath[[:space:]]*=/ {
            if (!has_append_windows_path) print "appendWindowsPath=false"
            has_append_windows_path = 1
            next
        }
        { print }
        END {
            append_missing(section)
            if (!has_boot) print "\n[boot]\nsystemd=true"
            if (!has_user) print "\n[user]\ndefault=" default_user
            if (!has_interop) print "\n[interop]\nappendWindowsPath=false"
        }
    ' "$source_file" > "$output_file"
}

configure_wsl() {
    if [ "$OS" != "wsl" ]; then
        return 20
    fi

    echo -e "${YELLOW}检查 WSL 配置...${NC}"

    local tmp_file source_file
    tmp_file="$(mktemp)"
    source_file=/etc/wsl.conf
    if [ ! -f "$source_file" ]; then
        source_file=/dev/null
    fi
    merge_wsl_config "$source_file" "$tmp_file"

    if [ -f /etc/wsl.conf ] && cmp -s "$tmp_file" /etc/wsl.conf; then
        echo -e "${GREEN}/etc/wsl.conf 已配置，跳过。${NC}"
        rm -f "$tmp_file"
        return 20
    fi

    echo -e "${CYAN}更新 /etc/wsl.conf，保留其他配置并关闭 Windows PATH 注入（需要 sudo）...${NC}"
    sudo install -m 0644 "$tmp_file" /etc/wsl.conf
    rm -f "$tmp_file"
    echo -e "${YELLOW}WSL 配置需在 Windows 中执行 wsl --shutdown 后重新打开才会完全生效。${NC}"
}

# ────────────────────────────────────────
# 函数：安装系统基础依赖
# ────────────────────────────────────────
install_system_packages() {
    echo -e "${YELLOW}检查系统基础依赖...${NC}"

    case $OS in
        "macos")
            if ! command -v brew &> /dev/null; then
                echo -e "${YELLOW}未检测到 Homebrew，请先安装 Homebrew 后继续。${NC}"
                return 1
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
            brew install "${brew_packages[@]}"
            ;;
        "linux"|"wsl")
            if ! command -v apt-get &> /dev/null; then
                echo -e "${YELLOW}当前 Linux 发行版未检测到 apt-get，跳过系统包自动安装。${NC}"
                return 20
            fi

            local apt_packages=(
                build-essential
                ca-certificates
                curl
                fd-find
                git
                git-extras
                gnupg
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
# GitHub 仓库：默认使用 public HTTPS；可用 DOTFILES_REPO_URL 覆盖
# ────────────────────────────────────────
SLUG="${DOTFILES_GITHUB_SLUG:-yangsx95/chezmoi}"
if [ -n "${DOTFILES_REPO_URL:-}" ]; then
    REPO_URL="$DOTFILES_REPO_URL"
else
    REPO_URL="https://github.com/${SLUG}.git"
fi

# ────────────────────────────────────────
# 函数：安装 chezmoi
# ────────────────────────────────────────
install_chezmoi() {
    echo -e "${YELLOW}检查 chezmoi 是否已安装...${NC}"

    if command -v chezmoi &> /dev/null; then
        echo -e "${GREEN}chezmoi 已安装，跳过安装步骤${NC}"
        return 20
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
        return 1
    fi

    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        echo -e "${CYAN}安装 oh-my-zsh...${NC}"
        local omz_installer
        omz_installer=$(mktemp)
        if curl -fsSL --max-time 60 https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$omz_installer"; then
            RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh "$omz_installer"
        else
            echo -e "${RED}oh-my-zsh 安装脚本下载失败。${NC}"
            rm -f "$omz_installer"
            return 1
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
        return 1
    fi
}

set_default_shell_zsh() {
    local zsh_path
    zsh_path="$(command -v zsh)"
    local current_shell
    if [ "$OS" = macos ]; then
        current_shell="$(dscl . -read "/Users/$USER" UserShell | awk '{print $2}')"
    else
        current_shell="$(getent passwd "$USER" | cut -d: -f7)"
    fi

    if [ "$current_shell" = "$zsh_path" ]; then
        echo -e "${GREEN}默认 shell 已是 zsh。${NC}"
        return
    fi

    if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
        echo -e "${CYAN}将 ${zsh_path} 加入 /etc/shells（需要 sudo）...${NC}"
        echo "$zsh_path" | sudo tee -a /etc/shells > /dev/null
    fi

    echo -e "${CYAN}设置默认 shell 为 zsh（可能需要输入密码）...${NC}"
    if chsh -s "$zsh_path" "$USER"; then
        echo -e "${GREEN}默认 shell 已设置为 zsh，新开终端后生效。${NC}"
    elif sudo chsh -s "$zsh_path" "$USER"; then
        echo -e "${GREEN}默认 shell 已通过 sudo 设置为 zsh，新开终端后生效。${NC}"
    else
        echo -e "${YELLOW}自动切换默认 shell 失败，可手动执行: sudo chsh -s ${zsh_path} ${USER}${NC}"
        return 1
    fi
}

# ────────────────────────────────────────
# 函数：安装 mise
# ────────────────────────────────────────
install_mise() {
    echo -e "${YELLOW}检查 mise 是否已安装...${NC}"

    if command -v mise &> /dev/null; then
        echo -e "${GREEN}mise 已安装，跳过安装步骤${NC}"
        return 20
    fi

    echo -e "${CYAN}正在安装 mise ...${NC}"

    case $OS in
        "macos")
            echo -e "${CYAN}使用 brew 安装 mise...${NC}"
            brew install mise
            ;;
        "linux"|"wsl")
            echo -e "${CYAN}使用 curl 安装 mise...${NC}"
            curl -fsSL --connect-timeout 20 --max-time 180 https://mise.jdx.dev/install.sh | sh
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

    local source_path status
    source_path=$(chezmoi source-path 2>/dev/null || true)
    if [ -n "$source_path" ] && git -C "$source_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        status=$(git -C "$source_path" status --porcelain --untracked-files=all) || return 1
        if [ -n "$status" ]; then
            echo '源仓库有未提交的修改或未跟踪文件，请先提交或自行暂存后重试。' >&2
            return 1
        fi
        status=$(chezmoi status --color=false) || return 1
        if printf '%s\n' "$status" | LC_ALL=C grep -q '^[ADM]'; then
            echo '受管理的目标文件有本地修改，请先用 chezmoi diff 检查并保留修改后重试。' >&2
            return 1
        fi
        # 保留用户的 remote、分支及 upstream；不强制覆盖或自动重新初始化。
        chezmoi update || return 1
        echo -e "${GREEN}chezmoi 更新完成${NC}"
    else
        chezmoi init --apply --branch main "$repo_url" || return 1
        echo -e "${GREEN}chezmoi 初始化完成${NC}"
    fi
}

# ────────────────────────────────────────
# 函数：安装 mise 声明的工具
# ────────────────────────────────────────
install_mise_tools() {
    if ! command -v mise &> /dev/null; then
        echo -e "${YELLOW}mise 未安装，无法执行工具安装，跳过${NC}"
        return 1
    fi

    export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

    echo -e "${CYAN}执行 mise install （安装 .mise.toml / .tool-versions 中声明的工具）...${NC}"

    if mise install; then
        echo -e "${GREEN}mise 工具安装完成${NC}"
    else
        echo -e "${RED}mise install 失败${NC}"
        return 1
    fi
}

# ────────────────────────────────────────
# VS Code（macOS：Homebrew；Linux：Microsoft apt 源）
# 跳过：DOTFILES_SKIP_VSCODE=1
# ────────────────────────────────────────
install_vscode() {
    if [ "${DOTFILES_SKIP_VSCODE:-}" = "1" ]; then
        echo -e "${YELLOW}已设置 DOTFILES_SKIP_VSCODE=1，跳过 VS Code 安装。${NC}"
        return 20
    fi

    if [ "$OS" = "wsl" ]; then
        echo -e "${YELLOW}WSL 环境跳过 VS Code GUI 安装。${NC}"
        return 20
    fi

    if command -v code &> /dev/null; then
        echo -e "${GREEN}VS Code 已安装，跳过安装步骤${NC}"
        return 20
    fi

    case "$OS" in
        macos)
            if ! command -v brew &> /dev/null; then
                echo -e "${YELLOW}无 Homebrew，跳过。可手动: brew install --cask visual-studio-code${NC}"
                return 1
            fi
            echo -e "${CYAN}通过 Homebrew 安装 VS Code (macOS)...${NC}"
            brew install --cask visual-studio-code
            ;;
        linux)
            if ! command -v apt-get &> /dev/null; then
                echo -e "${YELLOW}当前 Linux 发行版未检测到 apt-get，跳过 VS Code 自动安装。${NC}"
                echo -e "${YELLOW}请参考: https://code.visualstudio.com/docs/setup/linux${NC}"
                return 20
            fi

            echo -e "${CYAN}配置 Microsoft apt 源并安装 VS Code（需要 sudo）...${NC}"
            sudo install -m 0755 -d /etc/apt/keyrings
            local TMP_KEY
            TMP_KEY=$(mktemp)
            if curl -fsSL https://packages.microsoft.com/keys/microsoft.asc -o "$TMP_KEY" \
                && gpg --dearmor -o "${TMP_KEY}.gpg" "$TMP_KEY" \
                && sudo install -m 0644 "${TMP_KEY}.gpg" /etc/apt/keyrings/packages.microsoft.gpg; then
                rm -f "$TMP_KEY" "${TMP_KEY}.gpg"
            else
                rm -f "$TMP_KEY" "${TMP_KEY}.gpg"
                echo -e "${RED}Microsoft apt key 下载或安装失败，跳过 VS Code 安装。${NC}"
                return 1
            fi

            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
            sudo apt-get update
            sudo apt-get install -y code
            ;;
        *)
            echo -e "${YELLOW}当前 OS=$OS，未配置自动安装 VS Code。${NC}"
            ;;
    esac
}

# ────────────────────────────────────────
# JetBrains Toolbox
# 跳过：DOTFILES_SKIP_JETBRAINS_TOOLBOX=1
# ────────────────────────────────────────
install_jetbrains_toolbox() {
    if [ "${DOTFILES_SKIP_JETBRAINS_TOOLBOX:-}" = "1" ]; then
        echo -e "${YELLOW}已设置 DOTFILES_SKIP_JETBRAINS_TOOLBOX=1，跳过 JetBrains Toolbox 安装。${NC}"
        return 20
    fi

    if [ "$OS" = "wsl" ]; then
        echo -e "${YELLOW}WSL 环境跳过 JetBrains Toolbox GUI 安装。${NC}"
        return 20
    fi

    if command -v jetbrains-toolbox &> /dev/null; then
        echo -e "${GREEN}JetBrains Toolbox 已安装，跳过安装步骤${NC}"
        return 20
    fi

    case "$OS" in
        macos)
            if ! command -v brew &> /dev/null; then
                echo -e "${YELLOW}无 Homebrew，跳过。可手动: brew install --cask jetbrains-toolbox${NC}"
                return 1
            fi
            echo -e "${CYAN}通过 Homebrew 安装 JetBrains Toolbox (macOS)...${NC}"
            brew install --cask jetbrains-toolbox
            ;;
        linux)
            if ! command -v jq &> /dev/null; then
                echo -e "${YELLOW}未检测到 jq，无法解析 JetBrains Toolbox 最新版本，跳过。${NC}"
                return 1
            fi

            local API_URL="https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release"
            local DOWNLOAD_KEY="linux"
            local ARCH
            ARCH=$(uname -m)
            if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
                DOWNLOAD_KEY="linuxARM64"
            fi

            local TOOLBOX_URL
            TOOLBOX_URL=$(curl -fsSL --max-time 30 "$API_URL" | jq -r ".TBA[0].downloads.${DOWNLOAD_KEY}.link // empty")
            if [ -z "$TOOLBOX_URL" ]; then
                echo -e "${YELLOW}无法获取 JetBrains Toolbox 下载地址，请手动安装: https://www.jetbrains.com/toolbox-app/${NC}"
                return 1
            fi

            local TMP_TAR TMP_DIR INSTALL_DIR TOOLBOX_BIN
            TMP_TAR=$(mktemp /tmp/jetbrains-toolbox.XXXXXX.tar.gz)
            TMP_DIR=$(mktemp -d /tmp/jetbrains-toolbox.XXXXXX)
            INSTALL_DIR="${HOME}/.local/share/JetBrains/Toolbox"

            echo -e "${CYAN}下载 JetBrains Toolbox: ${TOOLBOX_URL} ...${NC}"
            if ! curl -fsSL --max-time 180 -o "$TMP_TAR" "$TOOLBOX_URL"; then
                echo -e "${RED}JetBrains Toolbox 下载失败${NC}"
                rm -rf "$TMP_TAR" "$TMP_DIR"
                return 1
            fi

            echo -e "${CYAN}安装 JetBrains Toolbox 到 ${INSTALL_DIR} ...${NC}"
            if ! tar -xzf "$TMP_TAR" -C "$TMP_DIR"; then
                echo -e "${RED}JetBrains Toolbox 解压失败${NC}"
                rm -rf "$TMP_TAR" "$TMP_DIR"
                return 1
            fi

            TOOLBOX_BIN=$(find "$TMP_DIR" -type f -name jetbrains-toolbox -perm -111 | head -1)
            if [ -z "$TOOLBOX_BIN" ]; then
                echo -e "${RED}未在安装包中找到 jetbrains-toolbox 可执行文件${NC}"
                rm -rf "$TMP_TAR" "$TMP_DIR"
                return 1
            fi

            mkdir -p "$INSTALL_DIR" "$HOME/.local/bin"
            cp -R "$(dirname "$TOOLBOX_BIN")/." "$INSTALL_DIR/"
            ln -sf "$INSTALL_DIR/jetbrains-toolbox" "$HOME/.local/bin/jetbrains-toolbox"
            rm -rf "$TMP_TAR" "$TMP_DIR"

            echo -e "${GREEN}JetBrains Toolbox 已安装到 ${INSTALL_DIR}${NC}"
            ;;
        *)
            echo -e "${YELLOW}当前 OS=$OS，未配置自动安装 JetBrains Toolbox。${NC}"
            ;;
    esac
}

# ────────────────────────────────────────
# GitHub Desktop（macOS：官方版；Linux：shiftkey 社区构建）
# 跳过：DOTFILES_SKIP_GITHUB_DESKTOP=1
# ────────────────────────────────────────
install_github_desktop() {
    if [ "${DOTFILES_SKIP_GITHUB_DESKTOP:-}" = "1" ]; then
        echo -e "${YELLOW}已设置 DOTFILES_SKIP_GITHUB_DESKTOP=1，跳过 GitHub Desktop 安装。${NC}"
        return 20
    fi

    if [ "$OS" = "wsl" ]; then
        echo -e "${YELLOW}WSL 环境跳过 GitHub Desktop GUI 安装。${NC}"
        return 20
    fi

    case "$OS" in
        macos)
            if ! command -v brew &> /dev/null; then
                echo -e "${YELLOW}无 Homebrew，跳过。可手动: brew install --cask github${NC}"
                return 1
            fi
            if brew list --cask github &> /dev/null; then
                echo -e "${GREEN}GitHub Desktop 已安装，跳过安装步骤${NC}"
                return 20
            fi
            echo -e "${CYAN}通过 Homebrew 安装 GitHub Desktop (macOS)...${NC}"
            brew install --cask github
            ;;
        linux)
            if command -v github-desktop &> /dev/null; then
                echo -e "${GREEN}GitHub Desktop 已安装，跳过安装步骤${NC}"
                return 20
            fi
            if ! command -v apt-get &> /dev/null || ! command -v dpkg &> /dev/null; then
                echo -e "${YELLOW}当前 Linux 发行版未检测到 apt/dpkg，跳过 GitHub Desktop 自动安装。${NC}"
                return 20
            fi
            if ! command -v jq &> /dev/null; then
                echo -e "${YELLOW}未检测到 jq，无法解析 GitHub Desktop 最新版本，跳过。${NC}"
                return 1
            fi

            local GH_DESKTOP_REPO="shiftkey/desktop"
            local API_URL="https://api.github.com/repos/${GH_DESKTOP_REPO}/releases/latest"
            local ARCH ASSET_PATTERN DESKTOP_URL
            ARCH=$(dpkg --print-architecture)
            case "$ARCH" in
                amd64) ASSET_PATTERN="(amd64|x86_64).*\\.deb$" ;;
                arm64) ASSET_PATTERN="(arm64|aarch64).*\\.deb$" ;;
                *)
                    echo -e "${YELLOW}GitHub Desktop 社区构建暂未配置架构 ${ARCH} 的自动安装。${NC}"
                    return 20
                    ;;
            esac

            DESKTOP_URL=$(curl -fsSL --max-time 30 "$API_URL" | jq -r ".assets[].browser_download_url | select(test(\"${ASSET_PATTERN}\"; \"i\"))" | head -1)
            if [ -z "$DESKTOP_URL" ]; then
                echo -e "${YELLOW}无法获取 GitHub Desktop Linux DEB 下载地址，请手动安装: https://github.com/${GH_DESKTOP_REPO}/releases${NC}"
                return 1
            fi

            local TMP_DEB
            TMP_DEB=$(mktemp /tmp/github-desktop.XXXXXX.deb)
            echo -e "${CYAN}下载 GitHub Desktop 社区构建: ${DESKTOP_URL} ...${NC}"
            if ! curl -fsSL --max-time 180 -o "$TMP_DEB" "$DESKTOP_URL"; then
                echo -e "${RED}GitHub Desktop 下载失败${NC}"
                rm -f "$TMP_DEB"
                return 1
            fi

            echo -e "${CYAN}安装 GitHub Desktop DEB 包（需要 sudo）...${NC}"
            if sudo dpkg -i "$TMP_DEB" 2>/dev/null; then
                echo -e "${GREEN}GitHub Desktop 安装完成${NC}"
            else
                sudo apt-get install -f -y
                sudo dpkg -i "$TMP_DEB"
            fi
            rm -f "$TMP_DEB"

            echo -e "${YELLOW}Linux/WSL 使用的是 shiftkey/desktop 社区构建，不是 GitHub 官方 Linux 版。${NC}"
            ;;
        *)
            echo -e "${YELLOW}当前 OS=$OS，未配置自动安装 GitHub Desktop。${NC}"
            ;;
    esac
}

# ────────────────────────────────────────
# 主流程
# ────────────────────────────────────────
# Each step runs outside an if/|| condition so Bash errexit remains active inside it.
STEP_RESULTS=()
FAILED_STEPS=0
run_step() {
    local label=$1 required=$2 code
    shift 2
    set +e
    ( set -e; set -o pipefail; "$@" )
    code=$?
    set -e
    case "$code" in
        0) STEP_RESULTS+=("成功: $label") ;;
        20) STEP_RESULTS+=("跳过: $label") ;;
        *) STEP_RESULTS+=("失败: $label (退出码 $code)"); FAILED_STEPS=$((FAILED_STEPS + 1)) ;;
    esac
    if [ "$code" -ne 0 ] && [ "$code" -ne 20 ] && [ "$required" = required ]; then
        print_summary
        exit 1
    fi
}

print_summary() {
    printf '\n安装结果：\n'
    printf '  %s\n' "${STEP_RESULTS[@]}"
    if [ "$FAILED_STEPS" -gt 0 ]; then
        printf '安装未全部完成；失败步骤请根据上方日志处理后重试。\n'
    else
        printf '所有执行的步骤均已成功；跳过项目见上表。\n'
    fi
}

main() {
    run_step 'WSL 配置' required configure_wsl
    run_step '系统基础依赖' required install_system_packages
    run_step 'chezmoi' required install_chezmoi
    run_step 'mise' required install_mise
    run_step 'zsh 配置' optional install_zsh_stack
    run_step 'dotfiles 初始化/更新' required init_or_update_chezmoi "$REPO_URL"
    run_step 'mise 工具链' optional install_mise_tools
    run_step 'VS Code' optional install_vscode
    run_step 'JetBrains Toolbox' optional install_jetbrains_toolbox
    run_step 'GitHub Desktop' optional install_github_desktop
    print_summary
    [ "$FAILED_STEPS" -eq 0 ] || return 1
    printf '\n请重新打开终端加载配置。日常更新：chezmoi update；检查差异：chezmoi diff。\n'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
