#Requires -Version 7
# 统一环境配置脚本 - 自动初始化或更新 dotfile 和 mise 配置
# 支持 Windows、macOS、Linux
# 可重复执行，用于首次初始化或后续更新

# winget 仅使用社区源，避免在未连通 Microsoft Store（msstore）时出现搜索失败 / 0x80072efd
$script:WingetSourceArgs = @("--source", "winget")

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  环境配置初始化/更新脚本开始执行  " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# ────────────────────────────────────────────────
#  1. 检测操作系统
# ────────────────────────────────────────────────
$OS = $null

if ($IsWindows -or $env:OS -eq "Windows_NT") {
    $OS = "windows"
}
elseif ($IsLinux) {
    $OS = "linux"
}
elseif ($IsMacOS) {
    $OS = "macos"
}

if (-not $OS) {
    Write-Host "无法识别当前操作系统，脚本退出。" -ForegroundColor Red
    exit 1
}

Write-Host "检测到系统类型: $OS" -ForegroundColor Green

# ────────────────────────────────────────────────
#  GitHub 仓库：勿写死令牌。DOTFILES_REPO_URL > GITHUB_TOKEN/GH_TOKEN > SSH
#  默认仓库：DOTFILES_GITHUB_SLUG = owner/repo（与 README 一致）
# ────────────────────────────────────────────────
$slug = if ($env:DOTFILES_GITHUB_SLUG) { $env:DOTFILES_GITHUB_SLUG } else { "yangsx95/chezmoi" }
if ($env:DOTFILES_REPO_URL) {
    $REPO_URL = $env:DOTFILES_REPO_URL
}
else {
    $token = $env:GITHUB_TOKEN
    if (-not $token) { $token = $env:GH_TOKEN }
    if ($token) {
        $REPO_URL = "https://${token}@github.com/${slug}.git"
    }
    else {
        $REPO_URL = "git@github.com:${slug}.git"
        Write-Host "未设置 GITHUB_TOKEN：将使用 SSH $REPO_URL（请确保已配置 ssh.github.com 密钥）" -ForegroundColor Yellow
    }
}

# ────────────────────────────────────────────────
#  函数：安装 chezmoi
# ────────────────────────────────────────────────
function Install-Chezmoi {
    Write-Host "检查 chezmoi 是否已安装..." -ForegroundColor Yellow

    if (Get-Command chezmoi -ErrorAction SilentlyContinue) {
        Write-Host "chezmoi 已安装，跳过安装步骤" -ForegroundColor Green
        return
    }

    Write-Host "正在安装 chezmoi ..." -ForegroundColor Cyan

    try {
        switch ($OS) {
            "windows" { winget install @script:WingetSourceArgs --id twpayne.chezmoi --exact --silent }
            "macos"   { brew install chezmoi }
            Default   {
                sh -c "$(curl -fsLS get.chezmoi.io)"
            }
        }
        Write-Host "chezmoi 安装成功" -ForegroundColor Green
    }
    catch {
        Write-Host "安装 chezmoi 失败: $_" -ForegroundColor Red
        exit 1
    }
}

# ────────────────────────────────────────────────
#  函数：安装 mise
# ────────────────────────────────────────────────
function Install-Mise {
    Write-Host "检查 mise 是否已安装..." -ForegroundColor Yellow

    if (Get-Command mise -ErrorAction SilentlyContinue) {
        Write-Host "mise 已安装，跳过安装步骤" -ForegroundColor Green
        return
    }

    Write-Host "正在安装 mise ..." -ForegroundColor Cyan

    try {
        switch ($OS) {
            "windows" { winget install @script:WingetSourceArgs --id jdx.mise --exact --silent }
            "macos"   { brew install mise }
            Default   {
                curl https://mise.jdx.dev/install.sh | sh
            }
        }
        Write-Host "mise 安装成功" -ForegroundColor Green
    }
    catch {
        Write-Host "安装 mise 失败: $_" -ForegroundColor Red
        exit 1
    }
}

# ────────────────────────────────────────────────
#  函数：初始化或更新 chezmoi
# ────────────────────────────────────────────────
function Initialize-Or-Update-Chezmoi {
    param (
        [Parameter(Mandatory = $true)]
        [string]$RepoUrl
    )

    Write-Host "处理 chezmoi 配置..." -ForegroundColor Yellow

    $sourcePath = $null
    try {
        $sourcePath = chezmoi source-path
    }
    catch {
        # 通常代表尚未初始化
    }

    if ($sourcePath) {
        Write-Host "已找到 chezmoi 仓库，正在尝试更新..." -ForegroundColor Cyan
        try {
            chezmoi update --force
            Write-Host "chezmoi 更新完成" -ForegroundColor Green
        }
        catch {
            Write-Host "更新失败: $_" -ForegroundColor Red
            $reinit = Read-Host "更新失败，是否强制重新初始化？(y/N)"
            if ($reinit -notmatch '^[yY]$') {
                Write-Host "用户取消，跳过重新初始化" -ForegroundColor Yellow
                return
            }

            Write-Host "执行强制重新初始化..." -ForegroundColor Cyan
            chezmoi init --apply --force $RepoUrl
            Write-Host "强制重新初始化完成" -ForegroundColor Green
        }
    }
    else {
        Write-Host "未找到 chezmoi 配置，开始初始化..." -ForegroundColor Cyan
        try {
            chezmoi init --apply $RepoUrl
            Write-Host "chezmoi 初始化完成" -ForegroundColor Green
        }
        catch {
            Write-Host "初始化失败: $_" -ForegroundColor Red
            exit 1
        }
    }
}

# ────────────────────────────────────────────────
#  函数：安装 mise 声明的工具
# ────────────────────────────────────────────────
function Install-MiseTools {
    if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
        Write-Host "mise 未安装，无法执行工具安装，跳过" -ForegroundColor Yellow
        return
    }

    Write-Host "执行 mise install （安装 .mise.toml / .tool-versions 中声明的工具）..." -ForegroundColor Cyan
    try {
        mise install
        Write-Host "mise 工具安装完成" -ForegroundColor Green
    }
    catch {
        Write-Host "mise install 失败: $_" -ForegroundColor Red
        # 不退出，让后续步骤继续执行
    }
}

# ────────────────────────────────────────────────
#  函数：安装 Anaconda（Windows 默认完整发行版 Anaconda.Anaconda3）
#  跳过：DOTFILES_SKIP_CONDA=1
#  安装根目录：DOTFILES_CONDA_ROOT（默认 D:\Anaconda3，需与 chezmoi 中 conda_root / ~/.condarc 一致）
#  其它包 ID：DOTFILES_CONDA_WINGET_ID（一般不必改）
#  NSIS 静默参数见：https://www.anaconda.com/docs/getting-started/anaconda/advanced-install/silent-mode
# ────────────────────────────────────────────────
function Install-Conda {
    if ($env:DOTFILES_SKIP_CONDA -eq "1") {
        Write-Host "已设置 DOTFILES_SKIP_CONDA=1，跳过 conda 安装。" -ForegroundColor Yellow
        return
    }
    if (Get-Command conda -ErrorAction SilentlyContinue) {
        Write-Host "conda 已在 PATH 中，跳过安装。" -ForegroundColor Green
        return
    }

    if ($OS -eq "windows") {
        $pkg = if ($env:DOTFILES_CONDA_WINGET_ID) { $env:DOTFILES_CONDA_WINGET_ID } else { "Anaconda.Anaconda3" }
        $condaRoot = if ($env:DOTFILES_CONDA_ROOT) { $env:DOTFILES_CONDA_ROOT } else { 'D:\Anaconda3' }
        # /D= 必须为安装程序最后一项；路径与 ~/.condarc、.chezmoi.toml.tmpl 中 conda_root 对齐
        $override = "/InstallationType=JustMe /AddToPath=1 /RegisterPython=1 /S /D=$condaRoot"
        Write-Host "正在通过 winget 安装 $pkg ，安装目录: $condaRoot ..." -ForegroundColor Cyan
        try {
            winget install @script:WingetSourceArgs --id $pkg --exact --silent --accept-package-agreements --accept-source-agreements --override $override
            Write-Host "winget 安装结束。请新开终端；若需 PowerShell 集成可执行: conda init powershell" -ForegroundColor Yellow
            Write-Host "包缓存与环境目录由 chezmoi 下发的 ~/.condarc 指定（默认 D:\conda\pkgs 与 D:\conda\envs）。首次请执行: chezmoi apply" -ForegroundColor Yellow
        }
        catch {
            Write-Host "conda 安装失败: $_" -ForegroundColor Red
        }
        return
    }

    if ($OS -eq "macos") {
        if (-not (Get-Command brew -ErrorAction SilentlyContinue)) {
            Write-Host "未检测到 Homebrew，无法自动安装 Miniconda。请安装 brew 后执行: brew install --cask miniconda" -ForegroundColor Yellow
            return
        }
        Write-Host "正在通过 Homebrew 安装 miniconda ..." -ForegroundColor Cyan
        try {
            brew install --cask miniconda
            Write-Host "安装完成。新开终端后执行 conda init zsh（或 bash）。" -ForegroundColor Yellow
        }
        catch {
            Write-Host "brew 安装 miniconda 失败: $_" -ForegroundColor Red
        }
        return
    }

    Write-Host "当前为 Linux：请在同目录执行 setup.sh，其中包含 Miniconda 安装脚本。" -ForegroundColor Yellow
}

# ────────────────────────────────────────────────
#  函数：安装 Clash 图形客户端（Windows 使用 winget）
#  跳过：DOTFILES_SKIP_CLASH=1
#  包 ID：DOTFILES_CLASH_WINGET_ID（默认 ClashVergeRev.ClashVergeRev；经典 CFW 用 Fndroid.ClashForWindows）
#  安装后请在客户端内开启系统代理或 TUN，并与 .chezmoi.toml.tmpl 中 proxy_url 端口一致（默认 7890）
# ────────────────────────────────────────────────
function Install-Clash {
    if ($env:DOTFILES_SKIP_CLASH -eq "1") {
        Write-Host "已设置 DOTFILES_SKIP_CLASH=1，跳过 Clash 安装。" -ForegroundColor Yellow
        return
    }
    if ($OS -ne "windows") {
        return
    }

    $pkg = if ($env:DOTFILES_CLASH_WINGET_ID) { $env:DOTFILES_CLASH_WINGET_ID } else { "ClashVergeRev.ClashVergeRev" }
    Write-Host "正在通过 winget 安装 Clash 客户端 ($pkg) ..." -ForegroundColor Cyan
    try {
        winget install @script:WingetSourceArgs --id $pkg --exact --silent --accept-package-agreements --accept-source-agreements
        Write-Host "Clash 客户端安装结束。请从开始菜单启动，导入订阅并开启代理（HTTP 端口建议与 proxy_url 一致）。" -ForegroundColor Yellow
    }
    catch {
        Write-Host "Clash 安装失败（可能已安装或网络问题）: $_" -ForegroundColor Red
    }
}

# ────────────────────────────────────────────────
#  主流程
# ────────────────────────────────────────────────
try {
    Install-Chezmoi
    Install-Mise
    Initialize-Or-Update-Chezmoi -RepoUrl $REPO_URL
    Install-MiseTools
    Install-Conda
    Install-Clash

    Write-Host "`n==========================================" -ForegroundColor Green
    Write-Host "        环境配置完成！        " -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green

    Write-Host "`n常用命令参考：" -ForegroundColor Cyan
    Write-Host "  • 更新配置      :  chezmoi update"
    Write-Host "  • 编辑文件      :  chezmoi edit ~/.zshrc"
    Write-Host "  • 强制应用      :  chezmoi apply -v"
    Write-Host "  • 进入仓库目录  :  cd (chezmoi source-path)"
}
catch {
    Write-Host "`n脚本执行过程中发生严重错误：" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

