# Windows wrapper: hcc targets Linux, so the build runs inside WSL2.
#
#   .\scripts\build.ps1            build the server
#   .\scripts\build.ps1 -Test      build and run the full test suite
#   .\scripts\build.ps1 -Toolchain install the holyc-lang compiler first
#
# See docs/PHASE0.md for why the build is not native.

param(
    [switch]$Test,
    [switch]$Toolchain,
    [string]$Distro = "Ubuntu"
)

$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot
$drive = $repo.Substring(0, 1).ToLower()
$wslPath = "/mnt/$drive" + $repo.Substring(2).Replace("\", "/")

function Invoke-Wsl([string]$cmd) {
    wsl.exe -d $Distro -e bash -lc "cd '$wslPath' && $cmd"
    if ($LASTEXITCODE -ne 0) { throw "failed (exit $LASTEXITCODE): $cmd" }
}

if ($Toolchain) { Invoke-Wsl "bash scripts/install-toolchain.sh" }

if ($Test) {
    Invoke-Wsl "bash scripts/run-tests.sh"
} else {
    Invoke-Wsl "bash scripts/build.sh"
}

Write-Host "binary: $repo\build\holy-nano-mcp (a Linux ELF - run it through WSL)"
