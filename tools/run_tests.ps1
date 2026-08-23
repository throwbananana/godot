<#
.SYNOPSIS
    跑 tools/test_*.gd 全家桶, 汇总结果, 并把每次跑的记录落到 logs/balance/。

.DESCRIPTION
    这个项目没有 GUT/GDUnit, 测试是一堆各自独立的 SceneTree 脚本, 各自 print
    [FAIL] 并以非零退出码结束, 而没有任何东西把它们聚合起来。后果是真实发生过
    的: 改了商店刷新定价之后 test_shop_and_attack_speed.gd 里的一条 assert 挂了,
    表现为 Godot **卡住九十秒**而不是报错; 而"把 35 个测试串起来跑一遍"会超过
    单条命令的时限被中途掐掉, 于是那次挂起被误当成超时, 一直没定位到。

    所以这里做三件事:
      1. 每个测试单独限时 (-TimeoutSec), 超时按失败计并明确标成 TIMEOUT ——
         挂起和失败要能分辨, 这正是上面那次踩的坑。
      2. 汇总 通过/失败/超时 三档, 有失败就整体非零退出 (给 CI 用)。
      3. 每个测试一行写进 logs/balance/testrun.jsonl, 字段和
         scripts/balance_log.gd 的格式对齐, 于是
         `python tools/analyze_balance_log.py --tests` 能看"哪个测试最近开始变慢/
         变得时灵时不灵"。测试本身也会往同一个目录写平衡数据 (curve_gate /
         route_shops), 两边同一个 _session, 可以对上。

.PARAMETER Filter
    只跑名字匹配的测试, 例如 -Filter balance

.PARAMETER TimeoutSec
    单个测试的时限, 默认 120 秒。

.PARAMETER Probe
    附带跑一次 tools/probe_balance_report.gd 采样探针 (慢, 约 4 分钟)。

.EXAMPLE
    pwsh tools/run_tests.ps1
    pwsh tools/run_tests.ps1 -Filter shop
    pwsh tools/run_tests.ps1 -Probe
#>
param(
    [string]$Filter = "",
    [int]$TimeoutSec = 120,
    [switch]$Probe
)

$ErrorActionPreference = "Stop"

# 必须用显式的 4.5 路径。PATH 上的 `godot` 是 4.7.1 的 Steam 版, 用它跑任何
# 会写项目的东西都会把 project.godot 往 4.7 上带 —— 见 CLAUDE.md。
$Godot = "C:\Godot\tools\Godot_v4.5-stable_win64.exe"
if (-not (Test-Path $Godot)) {
    Write-Error "找不到 Godot 4.5: $Godot"
    exit 2
}

$Root = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $Root "logs/balance"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$Commit = (& git -C $Root rev-parse --short=10 HEAD 2>$null)
if (-not $Commit) { $Commit = "unknown" }
$Session = "{0}_ps" -f [int][double]::Parse((Get-Date -UFormat %s))

$tests = Get-ChildItem (Join-Path $Root "tools") -Filter "test_*.gd" |
    Where-Object { $Filter -eq "" -or $_.Name -like "*$Filter*" } |
    Sort-Object Name

if ($tests.Count -eq 0) {
    Write-Output "没有匹配的测试 (filter='$Filter')"
    exit 1
}

Write-Output ("=" * 70)
Write-Output ("测试 {0} 个   commit={1}   session={2}   单个限时 {3}s" -f $tests.Count, $Commit, $Session, $TimeoutSec)
Write-Output ("=" * 70)

$rows = New-Object System.Collections.Generic.List[string]
$pass = 0; $fail = 0; $timeout = 0
$failed = New-Object System.Collections.Generic.List[string]

foreach ($t in $tests) {
    $rel = "tools/" + $t.Name
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # Start-Process + WaitForExit(ms) 才拿得到"超时"这个状态。直接调用的话
    # 挂住的进程会把整个脚本一起吊死, 那就退回到最初那个坑里了。
    $out = Join-Path ([System.IO.Path]::GetTempPath()) ("tt_" + $t.BaseName + ".log")
    $p = Start-Process -FilePath $Godot `
        -ArgumentList @("--headless", "--path", $Root, "--script", $rel) `
        -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError "$out.err"

    $status = ""
    if ($p.WaitForExit($TimeoutSec * 1000)) {
        $code = $p.ExitCode
        if ($code -eq 0) { $status = "PASS"; $pass++ }
        else { $status = "FAIL"; $fail++; $failed.Add($t.Name) }
    } else {
        try { $p.Kill() } catch {}
        $code = -1
        $status = "TIMEOUT"; $timeout++; $failed.Add($t.Name + " (超时)")
    }
    $sw.Stop()
    $dur = [math]::Round($sw.Elapsed.TotalSeconds, 2)

    $mark = switch ($status) { "PASS" { "  ok " } "FAIL" { "[FAIL]" } default { "[HANG]" } }
    Write-Output ("{0} {1,-44} {2,7:N2}s" -f $mark, $t.Name, $dur)

    if ($status -ne "PASS") {
        # 只回显失败测试里带 [FAIL]/❌ 的行 —— 完整输出留在临时文件里
        $lines = @()
        if (Test-Path $out) { $lines += Get-Content $out -ErrorAction SilentlyContinue }
        if (Test-Path "$out.err") { $lines += Get-Content "$out.err" -ErrorAction SilentlyContinue }
        $lines | Select-String -Pattern "\[FAIL\]|❌|SCRIPT ERROR|Parse Error" |
            Select-Object -First 8 | ForEach-Object { Write-Output ("        " + $_.Line.Trim()) }
        Write-Output ("        完整输出: " + $out)
    }

    $row = [ordered]@{
        _ts      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")
        _session = $Session
        _commit  = $Commit
        _cat     = "testrun"
        test     = $t.Name
        status   = $status
        exit_code = $code
        duration_s = $dur
        ok       = ($status -eq "PASS")
    }
    $rows.Add(($row | ConvertTo-Json -Compress))
}

# UTF8NoBOM: analyze_balance_log.py 按 utf-8 读, BOM 会让第一行 json.loads 失败
Add-Content -Path (Join-Path $LogDir "testrun.jsonl") -Value $rows -Encoding utf8NoBOM

Write-Output ("=" * 70)
Write-Output ("通过 {0}   失败 {1}   超时 {2}" -f $pass, $fail, $timeout)
if ($failed.Count -gt 0) {
    Write-Output ("失败清单: " + ($failed -join ", "))
}
Write-Output ("记录已写入 " + (Join-Path $LogDir "testrun.jsonl"))

if ($Probe) {
    Write-Output ""
    Write-Output "跑采样探针 (约 4 分钟)..."
    & $Godot --headless --path $Root --script "tools/probe_balance_report.gd"
}

Write-Output "分析: python tools/analyze_balance_log.py"
if ($fail + $timeout -gt 0) { exit 1 }
exit 0
