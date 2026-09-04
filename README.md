# chezmoi dotfiles

本仓库为 [chezmoi](https://www.chezmoi.io/) 源仓库，管理个人开发环境配置。

**开发模式**：Windows 作为宿主机，主要开发工作在 WSL2 中进行；macOS 作为备选开发平台。

## 快速开始

### WSL2（推荐）

```bash
# 1. 克隆仓库
git clone git@github.com:yangsx95/chezmoi.git ~/chezmoi-dotfiles
cd ~/chezmoi-dotfiles

# 2. 执行安装脚本（自动检测 WSL，安装基础包 + zsh + chezmoi + mise/uv 工具链 + IDE 工具）
chmod +x setup.sh && ./setup.sh
```

**前置要求**：
- WSL2 已安装并运行（Ubuntu 24.04 推荐）
- SSH 密钥已配置到 GitHub（`ssh -T git@github.com`）
- （可选）Windows 侧安装 [Windows Terminal](https://aka.ms/terminal) 作为终端

### macOS

```bash
git clone git@github.com:yangsx95/chezmoi.git ~/chezmoi-dotfiles
cd ~/chezmoi-dotfiles
chmod +x setup.sh && ./setup.sh
```

> **前置要求**：需先安装 [Homebrew](https://brew.sh/)。

### 已有 chezmoi 的更新

```bash
chezmoi update
```

---

## 安装脚本做了什么

`setup.sh` 依次执行：

| 步骤 | 说明 |
|------|------|
| 1. 检测系统 | 自动识别 macOS / Linux / WSL |
| 2. 安装系统基础包 | Ubuntu/WSL 用 apt 安装 zsh、git、curl、build-essential、jq、ripgrep 等；macOS 用 brew |
| 3. 安装 chezmoi | macOS 用 brew，Linux/WSL 安装到 `~/.local/bin` |
| 4. 安装 mise | macOS 用 brew，Linux/WSL 用官方脚本 |
| 5. 安装 zsh 栈 | 安装 oh-my-zsh、autosuggestions、syntax-highlighting，并尝试切换默认 shell 到 zsh |
| 6. chezmoi init/update | 初始化或更新 dotfiles 到 `$HOME` |
| 7. mise install | 安装 `.config/mise/config.toml` 中声明的工具（Java、Python、uv、Go、Node、Rust 等） |
| 8. VS Code（可选） | macOS 用 brew cask；Linux 配置 Microsoft apt 源安装 `code`，WSL 跳过 GUI 安装，`DOTFILES_SKIP_VSCODE=1` 跳过 |
| 9. JetBrains Toolbox（可选） | macOS 用 brew cask；Linux 下载官方 Toolbox，WSL 跳过 GUI 安装，`DOTFILES_SKIP_JETBRAINS_TOOLBOX=1` 跳过 |
| 10. GitHub Desktop（可选） | macOS 用官方 Homebrew cask；Linux 使用 `shiftkey/desktop` 社区 DEB 构建，WSL 跳过 GUI 安装，`DOTFILES_SKIP_GITHUB_DESKTOP=1` 跳过 |

---

## 包含的配置

### Shell 环境

| 文件 | 说明 |
|------|------|
| `.zshrc` | oh-my-zsh 配置，含插件（git、docker、python、node 等）、别名、mise 集成 |
| `.zprofile` | Login shell PATH 设置 |
| `.inputrc` | Readline 配置（bash/python 等历史搜索） |
| `.vimrc` | Vim 基础配置 |

### 开发工具

| 文件 | 说明 |
|------|------|
| `.config/mise/config.toml` | mise 全局工具：Java (zulu-8/17/21)、Python、uv、Go、Node (20/22/24)、Rust、maven、gradle；核心工具使用明确版本，避免 `latest` 导致重装漂移 |
| `.config/pip/pip.conf` | pip 阿里云镜像 |
| `.npmrc` | npm 全局配置 |
| `.gitconfig` | Git 全局配置（用户信息、别名、编码） |
| `.gitignore` | 全局 Git 忽略（IDE、系统文件） |
| `.gitattributes` | Git 换行符处理 |
| `.ssh/config` | SSH 客户端配置（GitHub via 443 端口） |

### Java 生态

| 文件 | 说明 |
|------|------|
| `.m2/settings.xml` | Maven 阿里云镜像 + 本地仓库路径 |
| `.gradle/gradle.properties` | Gradle 构建优化（缓存、并行、守护进程） |
| `.gradle/init.gradle` | Gradle 仓库优先级（mavenLocal → 阿里云 → Maven Central） |

### 容器与 CI

| 文件 | 说明 |
|------|------|
| `.docker/daemon.json` | Docker 镜像加速器（中国镜像） |
| `.config/gh/config.yml` | GitHub CLI 配置（SSH 协议） |

### sing-box

仓库管理 sing-box 的基础配置、路由顺序和小型个人黑白名单。节点凭据、
大型规则源及编译后的大型 `.srs` 文件保存在
`~/.local/share/sing-box/`，不会进入 Git。

```bash
sing-box-managed compile  # 编译个人规则并生成安全搜索 DNS 配置
sing-box-managed update   # 下载、编译、校验并应用启用的订阅
sing-box-managed dns-sync # 刷新 macOS 独立 DNS 过滤与节点白名单
sing-box-managed check    # 校验外部大规则及完整配置
sing-box-managed run      # 校验后以管理员权限运行
sing-box-managed status   # 查看进程和内存占用
```

所有路由规则与安全搜索订阅统一记录在
`~/.config/sing-box/rule-subscriptions.json`，通过 `type` 区分 `route-rule` 和
`dns-rewrite`。订阅原文与生成配置都保存在仓库外；运行 `sing-box-managed compile`
或 `update` 会自动刷新，下载、解析或校验失败时不会覆盖现有规则。

生成路由会劫持 TCP/UDP 53 到 sing-box DNS、拒绝 TCP/UDP 853，并使用 HaGeZi
的 DoH-only 域名与 IP 订阅阻断已知浏览器加密 DNS 端点。
macOS 额外使用本机 `dnscrypt-proxy`（`127.0.0.1:53`）；`compile`/`update`
会同时同步 OISD NSFW、本地阻断项以及代理节点白名单，使 sing-box 停止时仍有 DNS 过滤。

---

## WSL 特有说明

### 网络

仓库包含 `.wslconfig`（`networkingMode=mirrored`），可使 WSL2 与 Windows 共享 localhost：

```powershell
# 在 Windows PowerShell 中执行（chezmoi 无法自动部署到 Windows 侧）
copy .\dot_wslconfig.tmpl $env:USERPROFILE\.wslconfig
wsl --shutdown
wsl
```

## 日常使用

```bash
chezmoi update          # 拉取并应用最新配置
chezmoi edit ~/.zshrc   # 编辑配置文件
chezmoi diff            # 查看本地变更
chezmoi apply           # 应用变更
cd $(chezmoi source-path)  # 进入仓库目录
```

---

## 目录结构

```
~
├── .zshrc / .zprofile                # Shell 配置
├── .inputrc / .vimrc                 # 终端工具配置
├── .gitconfig / .gitignore / .gitattributes  # Git 配置
├── .npmrc                            # npm 配置
├── .config/
│   ├── mise/config.toml              # mise 工具版本
│   ├── pip/pip.conf                  # pip 镜像
│   └── gh/config.yml                 # GitHub CLI
├── .ssh/config                       # SSH 配置
├── .m2/settings.xml                  # Maven 配置
├── .gradle/                          # Gradle 配置
└── .docker/daemon.json               # Docker 镜像加速
```
