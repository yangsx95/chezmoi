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
`chezmoi apply` 会自动安装 sing-box 和 dnscrypt-proxy，并校验、部署 DNS 配置、
注册开机服务及设置系统 DNS。

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

## 安装与更新的保护措施

- `setup.sh` 更新已有仓库时保留 remote、当前分支和 upstream，不强制覆盖，也不自动重新初始化。
- 源仓库有未提交或未跟踪文件，或 chezmoi 检测到目标文件相对上次应用存在本地修改时，停止更新。先用 `git status`、`chezmoi diff` 检查；需要保留的目标修改可用 `chezmoi re-add` 收回源仓库，再审查提交。
- 安装结果按步骤显示成功、跳过或失败。基础依赖和 dotfiles 更新失败会停止；工具链或可选应用失败会继续后续步骤，但最终仍返回非零退出码。
- `tests/`、`.github/`、`.idea/` 和仓库说明文件不部署到家目录。此前已部署的 `~/tests/` 不会自动删除，请确认内容后自行清理。
- Shell 默认仅加载 Git、已安装的 autosuggestions 和 syntax-highlighting；保留 `.zshrc.local`、`.zshrc.work` 扩展入口，Node 警告正常显示。

安装保护逻辑可通过 `bash tests/setup-safety.sh` 在模拟环境中验证，不会执行真实安装。

## 音视频转文字（本机识别）

`media-to-text` 使用 [faster-whisper](https://github.com/SYSTRAN/faster-whisper)，在本机 CPU 上识别，不上传音频或视频。支持 macOS、Linux/WSL；PyAV 自带解码库，无需额外安装 FFmpeg。输入视频必须包含音轨，只转录语音，不识别画面文字或区分说话人。

依赖已有的 `uv`。首次运行会自动准备隔离的 Python 3.11 和固定版本的识别库，不修改全局 Python。首次模型下载需显式添加 `--download-model`；模型缓存放在 Hugging Face 默认缓存目录（通常为 `~/.cache/huggingface/hub`），不会进入本仓库。

```bash
# 应用命令文件（不运行其他 chezmoi 脚本）
chezmoi apply --exclude scripts ~/.local/bin/media-to-text

# 首次准备 small 模型并转录中文视频
media-to-text "会议.mp4" --language zh --download-model

# 后续使用本机缓存；彻底禁止 uv 联网可同时设置 UV_OFFLINE=1
UV_OFFLINE=1 media-to-text "会议.mp4" --language zh

# 不指定语言和模型：自动选择本机模型，再检测语种
UV_OFFLINE=1 media-to-text "录音.m4a"

# 自动检测语言，批量识别音频、视频，输出到指定目录
media-to-text "录音.m4a" "访谈.mp4" -o ./transcripts

# 使用更大的已缓存模型；本机已有 large-v3 缓存时可直接运行
media-to-text "录音.wav" --model large-v3 --language zh

# 其他输出格式（默认仅 SRT）
media-to-text "录音.mp3" --format txt
media-to-text "视频.mov" --format vtt
media-to-text "录音.m4a" --format json
media-to-text "视频.mp4" --format all

# 也支持本地 CTranslate2 模型目录
media-to-text "录音.wav" --model /path/to/model
```

默认仅生成 `会议.mp4.srt`；`--format all` 生成 TXT、SRT、VTT、JSON 四种文件，保留完整输入文件名以避免不同扩展名之间碰撞。已有输出不会覆盖；确认替换时加 `--overwrite`。批次中单个媒体解码/识别失败会继续处理其他文件，最终返回非零退出码。模型不存在或输出冲突会在处理前报错；无语音时 TXT/SRT 为空，VTT 保留文件头，JSON 保留元数据和空 segments 数组。输出使用 UTF-8。

VTT 使用 `WEBVTT` 文件头及小数点毫秒时间戳，可用于网页字幕。JSON 包含 `source`（输入文件名）、`language`（识别语言）、`duration`（音频总时长，秒）、`text`（全文）和 `segments`（每段的 `id`、`start`、`end`、`text`，时间单位为秒）。

省略 `--model`（或指定 `--model auto`）时，只检查本机完整缓存，依次选择 `small → medium → large-v3-turbo → large-v3 → large-v2 → large-v1 → base → tiny`，优先兼顾 CPU 速度和识别效果。明确指定 `--language en` 时，还会尝试英文专用和蒸馏模型；自动检测语言或中文不会误选英文专用模型。MLX 模型不兼容此后端，不参与选择。没有可用缓存时默认报错，只有显式加 `--download-model` 才下载 `small`。可用 `--model` 手动指定模型或路径；更大模型消耗更多内存与时间。当前使用 CPU/int8，不使用 Apple GPU；识别结果仍需校对，尤其是人名、数字和背景噪声较多的片段。

开发验证：`python3 tests/media-to-text.py`（不下载模型、不读取个人媒体）。

### 常用识别参数

```bash
# 只识别 10～15 分钟；字幕时间仍对应原视频
media-to-text "会议.mp4" --start 00:10:00 --end 00:15:00

# 提供术语背景，限制字幕每行字符数
media-to-text "会议.mp4" --initial-prompt "权限中台、DataGrip、租赁" --max-line-width 24

# 递归处理目录，跳过已有结果
media-to-text ./录音 --recursive --skip-existing -o ./transcripts

# 逐词字幕，以及 JSON 中的词级时间戳
media-to-text "视频.mp4" --word-timestamps --format all

# 控制资源，关闭静音过滤，隐藏进度
media-to-text "录音.wav" --threads 2 --no-vad --quiet
```

| 参数 | 行为 |
|---|---|
| `--start` / `--end` | 支持秒数、`MM:SS`、`HH:MM:SS`（含小数秒）；结束必须晚于开始，超出媒体末尾会截到末尾。先解码再裁剪，只识别选定片段；长媒体解码仍需要时间和内存。 |
| `--initial-prompt` | 提供人名或术语背景，不保证识别正确，也不是摘要指令。 |
| `--max-line-width` | 限制 SRT/VTT 每行字符数；中文字符按一个字符计，不是屏幕像素宽度。不改变 TXT/JSON 全文或字幕时间。 |
| `--skip-existing` | 跳过已存在的普通输出文件；`all` 模式只补齐缺失格式。不能与 `--overwrite` 同用；全部结果已存在时不加载模型。不会检查已有内容是否与当前参数匹配。 |
| `--recursive` | 按扩展名扫描目录中的常见音视频，跳过符号链接和指定输出目录。指定 `-o` 时保留输入根目录名及子目录层级，例如 `录音/会议/a.mp4` 输出到 `transcripts/录音/会议/a.mp4.srt`。 |
| `--word-timestamps` | SRT/VTT 每个词单独一条字幕；JSON 的每段新增 `words`（`start`、`end`、`word`、`probability`）。词的边界由模型决定，中文不一定按单字划分。TXT 保持全文。 |
| `--no-vad` | 关闭默认启用的静音过滤，可用于排查轻声漏识别，也可能增加静音误识别和耗时。 |
| `--threads` | CPU 线程数，正整数，默认 4。 |
| `--quiet` | 隐藏应用进度和汇总；仍向标准输出打印结果路径，向标准错误打印错误。首次运行时 uv 自身仍可能输出依赖准备日志。 |

默认在标准错误显示文件序号、根据已生成字幕估算的进度、已处理时长、单文件及总耗时；标准输出只放成功输出的文件路径。长时间静音或单段推理期间进度可能暂时不更新。JSON 另外记录 `clip_start`、`clip_end`（秒）；裁剪后的段和词时间戳仍使用原媒体时间轴，`duration` 保留原音频总时长。
