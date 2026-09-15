# 端到端联机测试的驱动脚本: 起两个 headless 进程, 真的连一次。
#
# 为什么要单独一个驱动而不是塞进 run_tests.ps1: 这个测试要同时跑两个进程、
# 占一个真实端口、并且总耗时约 25 秒 —— 和那边"每个测试一个进程、各自超时"
# 的模型不一样。run_tests.ps1 里的 test_net_e2e.gd 在缺参数时会自己跳过。
#
#   pwsh tools/run_net_e2e.ps1
#
# 退出码: 两端都通过才是 0。

param(
    [string]$Godot = "C:\Godot\tools\Godot_v4.5-stable_win64.exe",
    [int]$TimeoutSec = 120,
    # 只跑其中一趟, 调试用: -Only arcade / -Only campaign
    [string]$Only = ""
)

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $projectDir "logs\net_e2e"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

if (-not (Test-Path $Godot)) {
    Write-Host "[FAIL] 找不到 Godot: $Godot" -ForegroundColor Red
    exit 1
}

# 一趟 = 起两个进程连一次。街机那趟测复制/预测/建造请求, 战役那趟测战役
# 状态接管、房间流转、以及客户端存档不被改写。
function Invoke-Pass {
    param([string]$Name, [string[]]$Extra)

    $hostLog = Join-Path $logDir "$Name-host.log"
    $clientLog = Join-Path $logDir "$Name-client.log"

    Write-Host ""
    Write-Host "=== [$Name] 启动主机 ===" -ForegroundColor Cyan
    $baseArgs = @("--headless", "--path", $projectDir, "--script", "tools/test_net_e2e.gd", "--")
    $hostProc = Start-Process -FilePath $Godot `
        -ArgumentList ($baseArgs + @("--host") + $Extra) `
        -RedirectStandardOutput $hostLog -RedirectStandardError "$hostLog.err" `
        -PassThru -NoNewWindow

    # 主机要先把端口监听起来客户端才连得上。主机那边本来就会等客户端最多
    # CONNECT_TIMEOUT 秒, 所以这个数偏大只是让测试慢一点, 不会假失败。
    Start-Sleep -Seconds 2

    Write-Host "=== [$Name] 启动客户端 ===" -ForegroundColor Cyan
    $clientProc = Start-Process -FilePath $Godot `
        -ArgumentList ($baseArgs + @("--client") + $Extra) `
        -RedirectStandardOutput $clientLog -RedirectStandardError "$clientLog.err" `
        -PassThru -NoNewWindow

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    foreach ($p in @($hostProc, $clientProc)) {
        $remaining = [int]($deadline - (Get-Date)).TotalSeconds
        if ($remaining -lt 1) { $remaining = 1 }
        if (-not $p.WaitForExit($remaining * 1000)) {
            Write-Host "[TIMEOUT] 进程 $($p.Id) 超过 ${TimeoutSec}s 未退出, 强制结束" -ForegroundColor Red
            try { $p.Kill() } catch {}
        }
    }

    Write-Host "----- [$Name] 主机输出 -----" -ForegroundColor DarkGray
    # 必须 Write-Host 而不是直接让 Get-Content 落进管道 —— 函数的返回值是
    # **整个管道**, 那样布尔返回值会被这几十行日志淹掉, 于是 Invoke-Pass 的
    # 结果永远为真, 失败的那一趟会被报成通过 (第一版就是这样)。
    Get-Content $hostLog | Where-Object { $_ -match "^\s*\[|^====|^\[FAIL" } | ForEach-Object { Write-Host $_ }
    Write-Host "----- [$Name] 客户端输出 -----" -ForegroundColor DarkGray
    Get-Content $clientLog | Where-Object { $_ -match "^\s*\[|^====|^\[FAIL" } | ForEach-Object { Write-Host $_ }

    if ($hostProc.ExitCode -eq 0 -and $clientProc.ExitCode -eq 0) {
        Write-Host ">>> [$Name] PASSED" -ForegroundColor Green
        return $true
    }
    Write-Host "[FAIL] [$Name] 失败 (主机 $($hostProc.ExitCode) / 客户端 $($clientProc.ExitCode))" -ForegroundColor Red
    return $false
}

$allOk = $true
# lobby 趟走的是玩家真正的路径: 标题界面 -> 创建房间 -> UDP 广播发现 ->
# 点房间加入 -> 开始对战。前两趟为了聚焦复制层是直接调 host_game/join_game 的,
# 所以大厅和局域网发现本身只有这一趟测得到。放在最前面: 它要是不通,
# 后面两趟测的东西玩家根本走不到。
if ($Only -eq "" -or $Only -eq "lobby") {
    if (-not (Invoke-Pass -Name "lobby" -Extra @("--lobby"))) { $allOk = $false }
}
if ($Only -eq "" -or $Only -eq "arcade") {
    if (-not (Invoke-Pass -Name "arcade" -Extra @())) { $allOk = $false }
}
if ($Only -eq "" -or $Only -eq "campaign") {
    if (-not (Invoke-Pass -Name "campaign" -Extra @("--campaign"))) { $allOk = $false }
}

Write-Host ""
if ($allOk) {
    Write-Host ">>> NET E2E PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "[FAIL] NET E2E 失败 —— 完整日志: $logDir" -ForegroundColor Red
    exit 1
}
