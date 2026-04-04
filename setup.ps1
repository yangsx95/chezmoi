#Requires -Version 7
# 统一环境配置脚本 - 自动初始化或更新 dotfile 和 mise 配置
# 支持 Windows、macOS、Linux
# 可重复执行，用于首次初始化或后续更新

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
#  GitHub 仓库（含 token 示例，请替换为真实 token 或使用 SSH）
# ────────────────────────────────────────────────
$GITHUB_TOKEN = "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"   # ← 务必替换！
$REPO_URL     = "https://${GITHUB_TOKEN}@github.com/yangsx95/dotfiles.git"

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
            "windows" { winget install --id twpayne.chezmoi --exact --silent }
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
            "windows" { winget install --id jdx.mise --exact --silent }
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
#  主流程
# ────────────────────────────────────────────────
try {
    Install-Chezmoi
    Install-Mise
    Initialize-Or-Update-Chezmoi -RepoUrl $REPO_URL
    Install-MiseTools

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

