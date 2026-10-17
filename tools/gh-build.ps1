# Trigger or monitor GitHub Actions build for kiwix-ios6
param(
    [switch]$Watch,
    [switch]$Download
)

$cfg = Join-Path $PSScriptRoot "local.json"
if (-not (Test-Path $cfg)) {
    Write-Error "tools/local.json not found."
    exit 1
}

$local = Get-Content $cfg -Raw | ConvertFrom-Json
$repo = $local.repo
if (-not $repo) { $repo = "samcejko/kiwix-ios6" }

Write-Host "Triggering workflow on $repo..." -ForegroundColor Cyan
& gh workflow run build.yml --repo $repo

if ($Watch) {
    & gh run watch --repo $repo
}
