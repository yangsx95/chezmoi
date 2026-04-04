# 个人环境配置（chezmoi）

本仓库为 [chezmoi](https://www.chezmoi.io/) 源仓库，GitHub 地址：**`https://github.com/yangsx95/chezmoi`**。以下命令中的 `<github_api_token>` 需替换为你的 GitHub Personal Access Token（`repo` 权限）；**若已配置 SSH**，可改用文内 SSH 地址，无需把令牌写进命令行历史。

**GitHub API 令牌（给 zsh 里的 `GITHUB_API_TOKEN`）**：任选其一：在 **`chezmoi edit-config`** 打开的本地配置中于 `[data]` 设置 `github_api_token = "..."`；或在执行 **`chezmoi apply` 的环境中**设置环境变量 **`GITHUB_TOKEN`**（优先于 data）。若令牌曾出现在旧版本提交中，请到 GitHub 上**撤销并换新**。

## 系统环境配置指南

### 1. 安装依赖工具

按系统选择安装 **chezmoi** 与 **mise**：

| 系统 | chezmoi | mise |
|------|---------|------|
| Windows | `winget install --id twpayne.chezmoi --exact` | `winget install --id jdx.mise --exact` |
| macOS | `brew install chezmoi` | `brew install mise` |
| Linux | `sh -c "$(curl -fsLS get.chezmoi.io)"` | `curl https://mise.jdx.dev/install.sh \| sh` |

### 2. 初始化配置

```shell
# 方式 A：HTTPS + 令牌（将 <github_api_token> 换成你的 PAT）
chezmoi init --apply https://<github_api_token>@github.com/yangsx95/chezmoi.git

# 方式 B：SSH（本机已添加 GitHub SSH 公钥时）
# chezmoi init --apply git@github.com:yangsx95/chezmoi.git

# 安装 mise 声明的工具（.mise.toml / .tool-versions）
mise install
```

### 3. 日常操作

```shell
chezmoi update
chezmoi edit <文件名>
chezmoi apply
cd $(chezmoi source-path)
```

在 **Windows PowerShell** 中，最后一行建议写为：`cd (chezmoi source-path)`。

## 统一安装脚本

脚本可自动检测系统、安装缺失的 chezmoi / mise，并执行 `chezmoi init` 或 `chezmoi update` 以及 `mise install`。

| 系统 | 用法 |
|------|------|
| Windows | 在**本仓库根目录**（含 `setup.ps1`）下用 **PowerShell 7+** 执行 `.\setup.ps1` |
| Linux / macOS / WSL | 在**本仓库根目录**执行 `chmod +x setup.sh && ./setup.sh` |

私有仓库：请先配置 **SSH**，或设置环境变量 **`GITHUB_TOKEN`** / **`DOTFILES_REPO_URL`**。

脚本会依次：检测系统 → 按需安装 chezmoi、mise → 初始化或更新 chezmoi → `mise install` → **可选 Conda** → **可选 Clash 客户端**（见下两节）。

执行完成后，一般会安装工具、同步配置并写入环境变量；在已安装 PowerShell / zsh 等的前提下即可使用仓库中的 shell 配置。

### Anaconda / conda（setup 脚本 + `~/.condarc`）

[mise](https://mise.jdx.dev/) 可为项目安装 **CPython**（见 `dot_config/mise/config.toml.tmpl`），与 conda **不冲突**。

| 平台 | 默认行为 |
|------|----------|
| **Windows** | **`winget install Anaconda.Anaconda3`**（完整发行版，非 Miniconda），静默安装到 **`D:\Anaconda3`**（可用环境变量覆盖） |
| **macOS** | `brew install --cask miniconda`（需已安装 Homebrew） |
| **Linux / WSL** | 官方脚本静默安装到 **`~/miniconda3`** |

**Windows 下路径约定（可在 `.chezmoi.toml.tmpl` 的 `[data]` 中修改后 `chezmoi apply`）：**

| 项 | 默认 |
|----|------|
| Anaconda 安装根目录 | `D:/Anaconda3`（`conda_root`，与 `setup.ps1` 中 `DOTFILES_CONDA_ROOT` 一致） |
| 包下载缓存 `pkgs_dirs` | `D:/conda/pkgs` |
| 虚拟环境目录 `envs_dirs` | `D:/conda/envs` |

上述后两项由 **`dot_condarc.tmpl`** 生成 **`%USERPROFILE%\.condarc`**，在安装 Anaconda **之后**请执行 **`chezmoi apply`**，确保缓存与环境目录指向 D 盘。若先改安装盘，请同时改 `conda_root` 与 `DOTFILES_CONDA_ROOT`，再 `chezmoi apply`。

仅改安装目录（不改 winget 包名）：

```powershell
$env:DOTFILES_CONDA_ROOT = "E:\Anaconda3"
.\setup.ps1
```

**跳过 conda 安装**（仅 chezmoi + mise）：

```powershell
$env:DOTFILES_SKIP_CONDA = "1"
.\setup.ps1
```

```bash
export DOTFILES_SKIP_CONDA=1
./setup.sh
```

安装后若当前终端仍无 `conda`，请**新开终端**，并按提示执行 `conda init`（PowerShell / zsh / bash）。

### Clash 客户端（可选，setup 脚本）

可与下方 **`proxy_url`（默认 `http://127.0.0.1:7890`）** 配合：先装 **Clash 系 GUI**，在软件里开启**系统代理**或 **Mixed Port**，端口与 `proxy_url` 一致即可。

| 平台 | 默认行为 |
|------|----------|
| **Windows**（`setup.ps1`） | `winget install --source winget …`（仅 **winget** 源，避免连不上 **Microsoft Store** 源时报错 `msstore` / `0x80072efd`） |
| **macOS**（`setup.sh`） | `brew install --cask clash-verge-rev` |
| **Linux / WSL** | 脚本仅打印说明，请自行安装 [Release](https://github.com/clash-verge-rev/clash-verge-rev/releases) 或使用发行版包 |

若更习惯 **Clash for Windows**（旧版界面），在运行 `setup.ps1` 前：

```powershell
$env:DOTFILES_CLASH_WINGET_ID = "Fndroid.ClashForWindows"
.\setup.ps1
```

**跳过 Clash 安装**：

```powershell
$env:DOTFILES_SKIP_CLASH = "1"
.\setup.ps1
```

```bash
export DOTFILES_SKIP_CLASH=1
./setup.sh
```

若手动执行 `winget install` 仍提示 **搜索源时失败: msstore**，请加上 **`--source winget`**，或先修复网络/代理后再试。

## HTTP 代理（可选关闭）

登录 shell 时会根据 chezmoi 中的 `proxy_url` 设置 `http_proxy`、`https_proxy` 等（便于配合 Clash 等）。若不需要自动走代理：

- **改地址**：编辑数据源中的 `.chezmoi.toml.tmpl` 的 `proxy_url`，再 `chezmoi apply`。
- **长期关闭（新开终端生效）**：环境变量 `DOTFILES_USE_PROXY=0`（或 `false` / `off` / `no`），或创建空文件 `~/.config/dotfiles/no-proxy`（Windows：`%USERPROFILE%\.config\dotfiles\no-proxy`）。

```bash
mkdir -p ~/.config/dotfiles && touch ~/.config/dotfiles/no-proxy
```

```powershell
New-Item -ItemType File -Force -Path (Join-Path $HOME '.config/dotfiles/no-proxy')
```
- **当前会话**：PowerShell 使用 `proxy_off` / `proxy_on`；Bash/Zsh（已加载 `~/.proxyrc`）同样。

## mise 数据目录（Windows PowerShell）

`~/.profile.ps1` 会设置 `MISE_DATA_DIR` 并补齐 PATH（shims、Python Scripts）。优先级：

1. 已设置的环境变量 **`MISE_DATA_DIR`**（不覆盖）
2. 数据源 `.chezmoi.toml.tmpl` 中的 **`mise_data_dir`**（默认 `D:/mise`），修改后 `chezmoi apply`
3. 本机 `~/.config/chezmoi/chezmoi.toml` 的 `[data]` 中合并同名项

## GitHub 个人访问令牌创建指南

创建后把值写入本地 `chezmoi.toml` 的 `[data].github_api_token`（勿提交到 git），见上文。

1. 打开 [GitHub](https://github.com) 并登录  
2. Settings → Developer settings → Personal access tokens → Tokens (classic)  
3. Generate new token (classic)，勾选 **`repo`**  
4. 生成后复制保存（只显示一次）
