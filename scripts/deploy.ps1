# scripts/deploy.ps1 - Complete deployment pipeline for OCI Apps
[CmdletBinding()]
param(
    [string]$TerraformDir,
    [string]$GeneratedDir,
    [string]$SourcePiholeKey
)

$ErrorActionPreference = "Stop"

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$RootDir = Split-Path -Parent $ScriptDir
if (-not $TerraformDir) { $TerraformDir = Join-Path $RootDir "terraform" }
if (-not $GeneratedDir) { $GeneratedDir = Join-Path $RootDir "generated" }
if (-not $SourcePiholeKey) { $SourcePiholeKey = Join-Path (Split-Path -Parent $RootDir) "oci-pihole\generated\id_ed25519" }

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  OCI Apps Deployment Pipeline" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Terraform Dir:  $TerraformDir"
Write-Host "Generated Dir:  $GeneratedDir"
Write-Host "Pihole Key:     $SourcePiholeKey"

# 1. Apply Terraform
Write-Host "`n[1/7] Applying Terraform Infrastructure..." -ForegroundColor Yellow
terraform -chdir="$TerraformDir" init
terraform -chdir="$TerraformDir" apply -auto-approve

$outputs = terraform -chdir="$TerraformDir" output -json | ConvertFrom-Json
$publicIp = $outputs.public_ip.value
$keyPath = Join-Path $GeneratedDir "id_ed25519"

# Restrict Windows private key permissions
if (Test-Path $keyPath) {
    icacls "$keyPath" /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null
}

Write-Host "Provisioned Instance Public IP: $publicIp" -ForegroundColor Green

# 2. Wait for SSH Connectivity
Write-Host "`n[2/7] Waiting for SSH Connectivity..." -ForegroundColor Yellow
$sshOpts = @("-i", $keyPath, "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-o", "LogLevel=ERROR", "-o", "ConnectTimeout=5")

function Invoke-RemoteBash {
    param([string]$Script)
    $normalized = $Script -replace "`r`n", "`n"
    ssh @sshOpts ubuntu@$publicIp $normalized
}
$retries = 30
$connected = $false
for ($i = 1; $i -le $retries; $i++) {
    try {
        $res = ssh @sshOpts ubuntu@$publicIp "echo 'SSH_READY'" 2>$null
        if ($res -match "SSH_READY") {
            $connected = $true
            Write-Host "SSH connection established on attempt $i." -ForegroundColor Green
            break
        }
    } catch { }
    Write-Host "Waiting for SSH ($i/$retries)..."
    Start-Sleep -Seconds 5
}
if (-not $connected) {
    throw "Timed out waiting for SSH connectivity to $publicIp"
}

# 3. Wait for Cloud-Init Completion
Write-Host "`n[3/7] Waiting for Host Cloud-Init Provisioning..." -ForegroundColor Yellow
$cloudInitDone = $false
for ($i = 1; $i -le 40; $i++) {
    $status = ssh @sshOpts ubuntu@$publicIp "test -f /opt/provision_complete && echo 'READY' || echo 'PENDING'" 2>$null
    if ($status -match "READY") {
        $cloudInitDone = $true
        Write-Host "Host cloud-init provisioning completed." -ForegroundColor Green
        break
    }
    Write-Host "Waiting for cloud-init ($i/40)..."
    Start-Sleep -Seconds 5
}
if (-not $cloudInitDone) {
    throw "Timed out waiting for cloud-init provisioning."
}

# 4. Clone Repositories
Write-Host "`n[4/7] Cloning Application Repositories..." -ForegroundColor Yellow
Invoke-RemoteBash @"
set -e
if [ ! -d "/home/ubuntu/article-to-speech/.git" ]; then
    git clone https://github.com/devWhyqueue/article-to-speech.git /home/ubuntu/article-to-speech
else
    cd /home/ubuntu/article-to-speech && git pull
fi

if [ ! -d "/home/ubuntu/berlin-insider/.git" ]; then
    git clone https://github.com/devWhyqueue/berlin-insider.git /home/ubuntu/berlin-insider
else
    cd /home/ubuntu/berlin-insider && git pull
fi
"@

# 5. Migrate Secrets, Configs, SSL, and Data
Write-Host "`n[5/7] Migrating Secrets, SSL Certificates, and Persistent Data..." -ForegroundColor Yellow

$piholeTfDir = Join-Path (Split-Path -Parent $RootDir) "oci-pihole\terraform"
$piholeOutputs = terraform -chdir="$piholeTfDir" output -json | ConvertFrom-Json
$sourceIp = $piholeOutputs.public_ip.value
$sourceSshOpts = @("-i", $SourcePiholeKey, "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null")

Write-Host "Source Backup Instance IP: $sourceIp"

$tempDir = Join-Path $RootDir "scratch_migration"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

try {
    # 5a. Article-to-Speech secrets & runtime
    Write-Host "Migrating Article-to-Speech (.env, credentials, .runtime)..."
    $a2sEnvLines = ssh @sourceSshOpts ubuntu@$sourceIp "sudo cat /mnt/old_instance/home/ubuntu/article-to-speech/.env"
    $a2sEnvText = ($a2sEnvLines -join "`n")
    $localA2sEnvPath = Join-Path $tempDir "a2s.env"
    [System.IO.File]::WriteAllText($localA2sEnvPath, $a2sEnvText)
    scp @sshOpts $localA2sEnvPath ubuntu@${publicIp}:/home/ubuntu/article-to-speech/.env

    $localGcpKey = Join-Path (Split-Path -Parent $RootDir) "article-to-speech\gcp-service-account.json"
    if (Test-Path $localGcpKey) {
        scp @sshOpts $localGcpKey ubuntu@${publicIp}:/home/ubuntu/article-to-speech/gcp-service-account.json
    }

    $localA2sTar = Join-Path $tempDir "a2s_runtime.tar.gz"
    ssh @sourceSshOpts ubuntu@$sourceIp "sudo tar -czf /tmp/a2s_runtime.tar.gz -C /mnt/old_instance/home/ubuntu/article-to-speech .runtime && sudo chmod 644 /tmp/a2s_runtime.tar.gz"
    scp @sourceSshOpts ubuntu@${sourceIp}:/tmp/a2s_runtime.tar.gz $localA2sTar
    scp @sshOpts $localA2sTar ubuntu@${publicIp}:/tmp/a2s_runtime.tar.gz
    ssh @sshOpts ubuntu@$publicIp "tar -xzf /tmp/a2s_runtime.tar.gz -C /home/ubuntu/article-to-speech && rm -f /tmp/a2s_runtime.tar.gz"

    # 5b. Berlin-Insider secrets, SSL certs, Nginx site config & database
    Write-Host "Migrating Berlin-Insider (.env, SSL certs, Nginx site, database)..."
    $biEnvLines = ssh @sourceSshOpts ubuntu@$sourceIp "sudo cat /mnt/old_instance/home/ubuntu/berlin-insider/.env"
    $biEnvText = ($biEnvLines -join "`n")
    $biEnvUpdated = ($biEnvText -replace "TELEGRAM_WEBHOOK_IP=.*", "TELEGRAM_WEBHOOK_IP=$publicIp")
    $localBiEnvPath = Join-Path $tempDir "bi.env"
    [System.IO.File]::WriteAllText($localBiEnvPath, $biEnvUpdated)
    scp @sshOpts $localBiEnvPath ubuntu@${publicIp}:/home/ubuntu/berlin-insider/.env

    $localBiTar = Join-Path $tempDir "bi_data.tar.gz"
    ssh @sourceSshOpts ubuntu@$sourceIp "sudo tar -czf /tmp/bi_data.tar.gz -C /mnt/old_instance/home/ubuntu/berlin-insider .data && sudo chmod 644 /tmp/bi_data.tar.gz"
    scp @sourceSshOpts ubuntu@${sourceIp}:/tmp/bi_data.tar.gz $localBiTar
    scp @sshOpts $localBiTar ubuntu@${publicIp}:/tmp/bi_data.tar.gz
    ssh @sshOpts ubuntu@$publicIp "tar -xzf /tmp/bi_data.tar.gz -C /home/ubuntu/berlin-insider && rm -f /tmp/bi_data.tar.gz"

    $localSslTar = Join-Path $tempDir "nginx_ssl.tar.gz"
    ssh @sourceSshOpts ubuntu@$sourceIp "sudo tar -czf /tmp/nginx_ssl.tar.gz -C /mnt/old_instance/etc/nginx ssl && sudo chmod 644 /tmp/nginx_ssl.tar.gz"
    scp @sourceSshOpts ubuntu@${sourceIp}:/tmp/nginx_ssl.tar.gz $localSslTar
    scp @sshOpts $localSslTar ubuntu@${publicIp}:/tmp/nginx_ssl.tar.gz
    ssh @sshOpts ubuntu@$publicIp "sudo tar -xzf /tmp/nginx_ssl.tar.gz -C /etc/nginx && rm -f /tmp/nginx_ssl.tar.gz"

    $nginxSite = ssh @sourceSshOpts ubuntu@$sourceIp "sudo cat /mnt/old_instance/etc/nginx/sites-available/berlin-insider"
    $localNginxPath = Join-Path $tempDir "berlin-insider.conf"
    [System.IO.File]::WriteAllText($localNginxPath, ($nginxSite -join "`n"))
    scp @sshOpts $localNginxPath ubuntu@${publicIp}:/tmp/berlin-insider.conf
    ssh @sshOpts ubuntu@$publicIp "sudo mv /tmp/berlin-insider.conf /etc/nginx/sites-available/berlin-insider && sudo ln -sfn /etc/nginx/sites-available/berlin-insider /etc/nginx/sites-enabled/berlin-insider && sudo rm -f /etc/nginx/sites-enabled/default && sudo nginx -t && sudo systemctl reload nginx"
} finally {
    Remove-Item -Recurse -Force -Path $tempDir -ErrorAction SilentlyContinue
}

Invoke-RemoteBash @"
set -e
sudo usermod -aG docker ubuntu
sudo chown -R ubuntu:ubuntu /home/ubuntu/article-to-speech /home/ubuntu/berlin-insider
"@

# 6. Build and Launch Containers
Write-Host "`n[6/7] Building and Launching Docker Containers..." -ForegroundColor Yellow
Invoke-RemoteBash @"
set -e
echo '--- Starting Article-to-Speech ---'
cd /home/ubuntu/article-to-speech
sudo docker compose up -d --build

echo '--- Starting Berlin-Insider ---'
cd /home/ubuntu/berlin-insider
sudo docker compose up -d --build
"@

# 7. Run Validation
Write-Host "`n[7/7] Running Validation Suite..." -ForegroundColor Yellow
$validateScript = Join-Path $ScriptDir "validate.ps1"
& $validateScript -TerraformDir "$TerraformDir" -GeneratedDir "$GeneratedDir"
