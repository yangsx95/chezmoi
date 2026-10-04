param([ValidateSet('start','stop','restart','status','check','run','logs','help','proxy-list','proxy-use')][string]$Command = 'help', [string]$Selection)
$ErrorActionPreference = 'Stop'
$dataDir = Join-Path $env:USERPROFILE '.local\share\sing-box'
$configPath = Join-Path $dataDir 'windows-config.json'
$core = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\sing-box.exe'
function Get-ManagedProcess {
    @(Get-CimInstance Win32_Process -Filter "Name='sing-box.exe'" | Where-Object {
        $_.ExecutablePath -and $_.CommandLine -and $_.CommandLine.Contains($configPath)
    })
}
function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run sing-box-managed in an Administrator PowerShell (Windows TUN requires elevation).'
    }
}
function Test-Config {
    & $core check -c $configPath
    if ($LASTEXITCODE -ne 0) { throw 'Configuration validation failed.' }
}
function Prepare-Config {
    $physical = @(Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Select-Object -ExpandProperty ifIndex)
    $uplink = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' | Where-Object {
        $_.InterfaceIndex -in $physical
    } | Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
    if (-not $uplink) { throw 'No active physical uplink with a default route.' }
    & node (Join-Path $env:USERPROFILE '.local\libexec\sing-box-windows-prepare.mjs') $configPath $uplink.InterfaceAlias $core
    if ($LASTEXITCODE -ne 0) { throw 'Failed to prepare Windows DNS and uplink configuration.' }
}
function Stop-Managed {
    Get-ManagedProcess | ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction Stop }
    for ($i=0; $i -lt 20; $i++) {
        if (-not (Get-ManagedProcess)) { Write-Output 'sing-box stopped.'; return }
        Start-Sleep -Milliseconds 250
    }
    throw 'sing-box did not stop.'
}
function Test-HttpPath([string]$Label, [string[]]$NetworkArgs) {
    $healthLog = Join-Path $dataDir 'health-check.log'
    $errorFile = Join-Path $dataDir 'health-check-error.log'
    # Native stderr under Windows PowerShell must not bypass cleanup via
    # ErrorActionPreference=Stop. Record the exit code and message explicitly.
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $status = & curl.exe @NetworkArgs --silent --show-error --connect-timeout 5 --max-time 15 --output NUL --write-out '%{http_code}' https://www.gstatic.com/generate_204 2> $errorFile
        $resultCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $savedPreference }
    $detail = Get-Content $errorFile -Raw -ErrorAction SilentlyContinue
    $message = "$(Get-Date -Format o) $Label curl=$resultCode HTTP=$status $detail"
    Add-Content -LiteralPath $healthLog -Value $message
    if ($resultCode -ne 0 -or $status -ne '204') { Write-Host $message; return $false }
    return $true
}
function Wait-HttpPath([string]$Label, [string[]]$NetworkArgs) {
    # URLTest may switch nodes while the first connection is still pending.
    # Retry with a new connection rather than killing a healthy new selection.
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        if (Test-HttpPath "$Label attempt=$attempt/3" $NetworkArgs) { return $true }
        if ($attempt -lt 3) { Start-Sleep -Seconds 2 }
    }
    return $false
}
function Start-Managed {
    if (Get-ManagedProcess) { Write-Output 'sing-box is already running.'; return }
    $otherVpn = Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
        $_.InterfaceAlias -eq 'iKuuuVPN' -and $_.DestinationPrefix -in @('0.0.0.0/0','0.0.0.0/1','128.0.0.0/1')
    }
    if ($otherVpn) { throw 'iKuuuVPN is still routing traffic. Disconnect its VPN/TUN before starting sing-box-managed.' }
    Prepare-Config
    Test-Config
    $process = Start-Process -FilePath $core -ArgumentList @('run','-c',('"'+$configPath+'"')) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $dataDir 'stdout.log') -RedirectStandardError (Join-Path $dataDir 'stderr.log')
    Start-Sleep -Seconds 3
    $process.Refresh()
    if ($process.HasExited) { Get-Content (Join-Path $dataDir 'stderr.log') -Tail 15; throw 'sing-box failed to start.' }
    if (-not (Wait-HttpPath 'proxy' @('--proxy','http://127.0.0.1:7890'))) {
        Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
        throw 'Proxy health check failed; stopped this instance to restore routing. Check node availability with logs.'
    }
    if (-not (Wait-HttpPath 'system/TUN' @('--noproxy','*'))) {
        Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
        throw 'Proxy passed but system/TUN HTTP check failed; stopped this instance to restore routing. See logs.'
    }
    Write-Output "sing-box started (PID $($process.Id)); proxy and system/TUN HTTP checks passed."
}
try {
    switch ($Command) {
        'help' { 'sing-box-managed start|stop|restart|status|check|run|logs|proxy-list|proxy-use <auto|INDEX|NAME>' }
        'proxy-list' { & node (Join-Path $env:USERPROFILE '.local\libexec\sing-box-windows-proxy.mjs') list; exit $LASTEXITCODE }
        'proxy-use' { & node (Join-Path $env:USERPROFILE '.local\libexec\sing-box-windows-proxy.mjs') use $Selection; exit $LASTEXITCODE }
        'check' { Test-Config }
        'status' {
            $running = Get-ManagedProcess
            if ($running) { $running | Select-Object ProcessId,ExecutablePath }
            else { 'sing-box is not running.'; exit 1 }
        }
        'logs' { Get-Content (Join-Path $dataDir 'stderr.log') -Tail 50 -ErrorAction SilentlyContinue; Get-Content (Join-Path $dataDir 'health-check.log') -Tail 10 -ErrorAction SilentlyContinue }
        'start' { Assert-Admin; Start-Managed }
        'stop' { Assert-Admin; Stop-Managed }
        'restart' { Assert-Admin; Test-Config; Stop-Managed; Start-Managed }
        'run' { Assert-Admin; if (Get-ManagedProcess) { throw 'Stop the running instance first.' }; Prepare-Config; Test-Config; & $core run -c $configPath; exit $LASTEXITCODE }
    }
} catch { Write-Error $_; exit 1 }
