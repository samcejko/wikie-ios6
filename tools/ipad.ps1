# Helpers for talking to the jailbroken iPad over SSH for Kiwix iOS 6:
#   . .\tools\ipad.ps1
#   Invoke-IPad 'uname -a'
#   Install-IPadDeb .\packages\com.samcejko.kiwix_1.0.0_iphoneos-arm.deb

$script:IPadKey = Join-Path $env:USERPROFILE '.ssh\ipad_ios6'
$script:IPadDefaultHost = '192.168.1.166'
$script:IPadLocalCfg = Join-Path $PSScriptRoot 'local.json'
if (Test-Path $script:IPadLocalCfg) {
    try {
        $c = Get-Content $script:IPadLocalCfg -Raw | ConvertFrom-Json
        if ($c.ipad) { $script:IPadDefaultHost = $c.ipad }
    } catch {}
}

function Get-IPadSshArgs {
    @('-i', $script:IPadKey, '-oHostKeyAlgorithms=+ssh-rsa', '-oStrictHostKeyChecking=accept-new', '-oConnectTimeout=10', '-oBatchMode=yes', '-oLogLevel=ERROR')
}

function Assert-IPadHost([string]$IPadHost) {
    if (-not $IPadHost) { throw 'No iPad address: set "ipad" in tools/local.json or pass -IPadHost' }
}

function Invoke-IPad {
    param([Parameter(Mandatory = $true)][string]$Command, [string]$IPadHost = $script:IPadDefaultHost)
    Assert-IPadHost $IPadHost
    $ErrorActionPreference = 'Continue'
    $sshArgs = Get-IPadSshArgs
    & ssh $sshArgs ("root@" + $IPadHost) $Command
}

function Install-IPadDeb {
    param([Parameter(Mandatory = $true)][string]$DebPath, [string]$IPadHost = $script:IPadDefaultHost)
    Assert-IPadHost $IPadHost
    if (-not (Test-Path $DebPath)) { throw "Deb file not found: $DebPath" }

    $sshArgs = Get-IPadSshArgs
    $debName = Split-Path $DebPath -Leaf
    $remotePath = "/tmp/$debName"

    Write-Host "Copying $debName to iPad..." -ForegroundColor Cyan
    & scp $sshArgs $DebPath ("root@$IPadHost`:$remotePath")

    Write-Host "Installing on iPad..." -ForegroundColor Cyan
    Invoke-IPad "dpkg -i $remotePath && rm -f $remotePath && uicache" -IPadHost $IPadHost
    Write-Host "Installed and uicache updated!" -ForegroundColor Green
}
