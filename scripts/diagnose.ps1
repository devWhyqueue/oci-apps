# scripts/diagnose.ps1 - Comprehensive diagnostics for OCI Apps host
[CmdletBinding()]
param(
    [string]$TerraformDir,
    [string]$GeneratedDir
)

$ErrorActionPreference = "Continue"

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$RootDir = Split-Path -Parent $ScriptDir
if (-not $TerraformDir) { $TerraformDir = Join-Path $RootDir "terraform" }
if (-not $GeneratedDir) { $GeneratedDir = Join-Path $RootDir "generated" }

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  OCI Apps (Article2Speech & Berlin Insider)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Read Terraform state / outputs
Write-Host "`n--- 1. TERRAFORM STATUS ---" -ForegroundColor Yellow
try {
    $outputs = terraform -chdir="$TerraformDir" output -json | ConvertFrom-Json
    $publicIp = $outputs.public_ip.value
    $instanceName = $outputs.instance_name.value
    $ad = $outputs.availability_domain.value
    $expectedCost = $outputs.expected_cost.value

    Write-Host "Instance:            $instanceName"
    Write-Host "Public IP:           $publicIp"
    Write-Host "Availability Domain: $ad"
    Write-Host "Cost:                $expectedCost"
} catch {
    Write-Host "Error reading Terraform outputs: $_" -ForegroundColor Red
    return
}

# 2. Local Artifacts
Write-Host "`n--- 2. LOCAL ARTIFACTS ---" -ForegroundColor Yellow
$artifacts = @(
    "id_ed25519",
    "id_ed25519.pub"
)
foreach ($file in $artifacts) {
    $filePath = Join-Path $GeneratedDir $file
    if (Test-Path $filePath) {
        Write-Host "  [OK] $file exists ($((Get-Item $filePath).Length) bytes)" -ForegroundColor Green
    } else {
        Write-Host "  [MISSING] $file does not exist" -ForegroundColor Red
    }
}

# 3. SSH Connectivity
Write-Host "`n--- 3. REMOTE SSH CONNECTIVITY ---" -ForegroundColor Yellow
$keyPath = Join-Path $GeneratedDir "id_ed25519"
if (-not (Test-Path $keyPath)) {
    Write-Host "SSH key missing at $keyPath" -ForegroundColor Red
    return
}
icacls "$keyPath" /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null

$sshOpts = @("-i", $keyPath, "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-o", "ConnectTimeout=10")

# 4. Remote System Diagnostics
Write-Host "`n--- 4. VM SYSTEM HEALTH ---" -ForegroundColor Yellow
ssh @sshOpts ubuntu@$publicIp @"
echo '=== UPTIME & LOAD ==='
uptime
echo '=== MEMORY USAGE ==='
free -h
echo '=== DISK SPACE ==='
df -h /
"@

# 5. Docker Containers
Write-Host "`n--- 5. DOCKER STATUS ---" -ForegroundColor Yellow
ssh @sshOpts ubuntu@$publicIp @"
echo '=== DOCKER CONTAINERS ==='
sudo docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
echo '=== ARTICLE-TO-SPEECH LOGS (LAST 15 LINES) ==='
sudo docker logs --tail 15 article-to-speech-app-1 2>/dev/null || sudo docker logs --tail 15 article-to-speech-app 2>/dev/null || echo 'No logs'
echo '=== BERLIN-INSIDER LOGS (LAST 15 LINES) ==='
sudo docker logs --tail 15 berlin-insider 2>/dev/null || echo 'No logs'
"@

# 6. Nginx & Firewall
Write-Host "`n--- 6. NGINX & FIREWALL STATUS ---" -ForegroundColor Yellow
ssh @sshOpts ubuntu@$publicIp @"
echo '=== NGINX STATUS ==='
sudo systemctl status nginx --no-pager -l | head -n 10
echo '=== LISTENING PORTS ==='
sudo ss -tulpn | grep -E ':(22|80|443|8080)\b'
echo '=== UFW STATUS ==='
sudo ufw status verbose
"@

Write-Host "`nDiagnostics run complete." -ForegroundColor Cyan
