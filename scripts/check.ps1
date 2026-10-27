# Runs every static check: sourcemap, luau-lsp analyze (strict types vs the Roblox API), selene, rojo build.
# Usage: .\scripts\check.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$env:Path = "$env:USERPROFILE\.rokit\bin;$env:Path"

$defs = Join-Path $root ".luau-defs\globalTypes.d.luau"
if (-not (Test-Path $defs)) {
    New-Item -ItemType Directory -Force (Split-Path $defs) | Out-Null
    Write-Host "== downloading Roblox API definitions"
    Invoke-WebRequest "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/1.36.0/scripts/globalTypes.d.luau" -OutFile $defs
}

Write-Host "== fix models"
& (Join-Path $PSScriptRoot "fix-models.ps1")

Write-Host "== rojo sourcemap"
rojo sourcemap default.project.json -o sourcemap.json
if ($LASTEXITCODE -ne 0) { throw "rojo sourcemap failed" }

Write-Host "== luau-lsp analyze"
luau-lsp analyze --definitions=$defs --sourcemap=sourcemap.json --ignore="Packages/**" --ignore="ServerPackages/**" src
if ($LASTEXITCODE -ne 0) { throw "luau-lsp analyze failed" }

Write-Host "== selene"
selene src
if ($LASTEXITCODE -ne 0) { throw "selene failed" }

Write-Host "== rojo build"
New-Item -ItemType Directory -Force build | Out-Null
rojo build default.project.json -o build/CrazyFare-fresh.rbxl
if ($LASTEXITCODE -ne 0) { throw "rojo build failed" }

Write-Host "ALL CLEAN"
