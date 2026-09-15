#!/usr/bin/env pwsh
# tools/export_itch.ps1  —  Build Tank Battle and upload to itch.io via butler
#
# Usage:
#   pwsh tools/export_itch.ps1                     # build both platforms + upload
#   pwsh tools/export_itch.ps1 -Channel windows    # Windows only
#   pwsh tools/export_itch.ps1 -Channel web        # Web only
#   pwsh tools/export_itch.ps1 -SkipBuild          # skip Godot export, upload existing build/ dir
#
# Prerequisites:
#   1. Godot 4.5 export templates installed in %APPDATA%\Godot\export_templates\4.5-stable\
#   2. butler installed and "butler login" completed
#   3. Set $itchUser and $itchGame below

param(
    [switch]$SkipBuild,
    [ValidateSet("windows", "web", "both")]
    [string]$Channel = "both"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Configuration (EDIT THESE) ───────────────────────────────────────────────
$godot    = "C:\Godot\tools\Godot_v4.5-stable_win64.exe"
$itchUser = "throwbananana"   # <- your itch.io username
$itchGame = "tank-battle"          # <- your game slug on itch.io
# ─────────────────────────────────────────────────────────────────────────────

$projectRoot = (Split-Path $PSScriptRoot -Parent)
$buildDir    = Join-Path $projectRoot "build"

function Export-Platform([string]$presetName, [string]$outputDir) {
    Write-Host "`n[BUILD] Exporting: $presetName" -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    & $godot --headless --path $projectRoot --export-release $presetName 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Godot export failed ($LASTEXITCODE): $presetName" }
    Write-Host "[BUILD] OK → $outputDir" -ForegroundColor Green
}

function Push-ToItch([string]$dir, [string]$channel) {
    $absDir = Resolve-Path $dir -ErrorAction SilentlyContinue
    if (-not $absDir) { throw "Build dir not found: $dir" }
    Write-Host "`n[PUSH] ${itchUser}/${itchGame}:${channel}" -ForegroundColor Yellow
    & butler push $absDir "${itchUser}/${itchGame}:${channel}"
    if ($LASTEXITCODE -ne 0) { throw "butler push failed: $channel" }
    Write-Host "[PUSH] Done: $channel" -ForegroundColor Green
}

if (-not (Test-Path $godot)) { throw "Godot 4.5 not found at: $godot" }
if (-not $itchUser -or $itchUser -eq "YOUR_USERNAME") { throw "Set itchUser/itchGame in tools/export_itch.ps1" }

if (-not $SkipBuild) {
    if ($Channel -in @("windows","both")) { Export-Platform "Windows Desktop" "$buildDir\windows" }
    if ($Channel -in @("web","both"))     { Export-Platform "Web"             "$buildDir\web"     }
}

if ($Channel -in @("windows","both")) { Push-ToItch "$buildDir\windows" "windows" }
if ($Channel -in @("web","both"))     { Push-ToItch "$buildDir\web"     "html5"   }

Write-Host "`n✅ Done! https://$itchUser.itch.io/$itchGame" -ForegroundColor Green


