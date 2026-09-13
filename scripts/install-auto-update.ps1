# scripts/install-auto-update.ps1 - Install systemd timer that auto-pulls & rebuilds both apps
[CmdletBinding()]
param(
    [string]$TerraformDir,
    [string]$GeneratedDir
)

$ErrorActionPreference = "Stop"

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$RootDir = Split-Path -Parent $ScriptDir
if (-not $TerraformDir) { $TerraformDir = Join-Path $RootDir "terraform" }
if (-not $GeneratedDir) { $GeneratedDir = Join-Path $RootDir "generated" }

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Installing OCI Apps Auto-Update Timer" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$outputs = terraform -chdir="$TerraformDir" output -json | ConvertFrom-Json
$publicIp = $outputs.public_ip.value
$keyPath = Join-Path $GeneratedDir "id_ed25519"

if (-not (Test-Path $keyPath)) {
    throw "Private SSH key not found at $keyPath"
}
icacls "$keyPath" /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null

$sshOpts = @("-i", $keyPath, "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-o", "LogLevel=ERROR", "-o", "ConnectTimeout=10")

function Invoke-RemoteBash {
    param([string]$Script)
    $normalized = $Script -replace "`r`n", "`n"
    ssh @sshOpts ubuntu@$publicIp $normalized
}

Write-Host "Target Host IP: $publicIp" -ForegroundColor Green

Write-Host "`nWriting oci-apps-update.sh..." -ForegroundColor Yellow
Invoke-RemoteBash @'
sudo tee /usr/local/bin/oci-apps-update.sh > /dev/null <<'SCRIPT'
#!/bin/bash
rc=0
for app in article-to-speech berlin-insider; do
  (
    set -e
    cd /home/ubuntu/$app
    git fetch -q origin main
    old=$(git rev-parse HEAD)
    [ "$old" = "$(git rev-parse origin/main)" ] && exit 0
    git merge -q --ff-only origin/main
    echo "$app: $old -> $(git rev-parse HEAD)"
    # build fail: roll back HEAD so next tick retries; old container keeps running
    docker compose up -d --build || { git reset -q --hard "$old"; exit 1; }
  ) || rc=1
done
docker image prune -f >/dev/null   # rebuilds leave dangling images; 50 GB disk
exit $rc
SCRIPT
sudo chmod +x /usr/local/bin/oci-apps-update.sh
'@

Write-Host "Writing oci-apps-update.service..." -ForegroundColor Yellow
Invoke-RemoteBash @'
sudo tee /etc/systemd/system/oci-apps-update.service > /dev/null <<'UNIT'
[Unit]
Description=Pull and rebuild oci-apps from git main

[Service]
Type=oneshot
User=ubuntu
ExecStart=/usr/local/bin/oci-apps-update.sh
UNIT
'@

Write-Host "Writing oci-apps-update.timer..." -ForegroundColor Yellow
Invoke-RemoteBash @'
sudo tee /etc/systemd/system/oci-apps-update.timer > /dev/null <<'UNIT'
[Unit]
Description=Periodically pull and rebuild oci-apps

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
UNIT
'@

Write-Host "Enabling timer..." -ForegroundColor Yellow
Invoke-RemoteBash @'
sudo systemctl daemon-reload
sudo systemctl enable --now oci-apps-update.timer
'@

Write-Host "`n==========================================" -ForegroundColor Green
Write-Host "  Auto-update timer installed!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
