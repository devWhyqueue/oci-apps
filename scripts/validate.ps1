# scripts/validate.ps1 - Automated verification for OCI Apps deployment
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
Write-Host "  Validating OCI Apps Deployment" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Read Terraform outputs
Write-Host "`n[1/6] Reading Terraform Outputs..." -ForegroundColor Yellow
$outputs = terraform -chdir="$TerraformDir" output -json | ConvertFrom-Json
$publicIp = $outputs.public_ip.value
Write-Host "Target Host IP: $publicIp" -ForegroundColor Green

# 2. SSH Connection Check
Write-Host "`n[2/6] Verifying SSH Access..." -ForegroundColor Yellow
$keyPath = Join-Path $GeneratedDir "id_ed25519"
if (-not (Test-Path $keyPath)) {
    throw "Private SSH key not found at $keyPath"
}
icacls "$keyPath" /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null
$sshOpts = @("-i", $keyPath, "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-o", "ConnectTimeout=10")

$sshCheck = ssh @sshOpts ubuntu@$publicIp "echo 'SSH_OK'" 2>$null
if ($sshCheck -match "SSH_OK") {
    Write-Host "  [PASS] SSH connection established." -ForegroundColor Green
} else {
    throw "Failed to connect via SSH to $publicIp"
}

# 3. Cloud-Init Completion
Write-Host "`n[3/6] Verifying Cloud-Init Provisioning..." -ForegroundColor Yellow
$cloudInitCheck = ssh @sshOpts ubuntu@$publicIp "test -f /opt/provision_complete && echo 'PROVISION_OK' || echo 'WAIT'" 2>$null
if ($cloudInitCheck -match "PROVISION_OK") {
    Write-Host "  [PASS] Host provisioning is complete." -ForegroundColor Green
} else {
    throw "Cloud-init host provisioning is still pending or incomplete."
}

# 4. Article-to-Speech Container Status
Write-Host "`n[4/6] Verifying Article-to-Speech..." -ForegroundColor Yellow
$a2sStatus = ssh @sshOpts ubuntu@$publicIp "sudo docker ps --filter 'name=article-to-speech' --format '{{.Names}}|{{.Status}}'" 2>$null
Write-Host "  Container status: $a2sStatus"
if ($a2sStatus -match "Up") {
    Write-Host "  [PASS] Article-to-speech container is running." -ForegroundColor Green
} else {
    throw "Article-to-speech container is not running!"
}

# 5. Berlin Insider Container Status & Endpoints
Write-Host "`n[5/6] Verifying Berlin Insider Container..." -ForegroundColor Yellow
$biStatus = ssh @sshOpts ubuntu@$publicIp "sudo docker ps --filter 'name=berlin-insider' --format '{{.Names}}|{{.Status}}'" 2>$null
Write-Host "  Container status: $biStatus"
if ($biStatus -match "Up") {
    Write-Host "  [PASS] Berlin-insider container is running." -ForegroundColor Green
} else {
    throw "Berlin-insider container is not running!"
}

# 6. HTTP / HTTPS and Nginx Reverse Proxy Validation
Write-Host "`n[6/6] Verifying Nginx Reverse Proxy & HTTP Endpoints..." -ForegroundColor Yellow
$httpTests = ssh @sshOpts ubuntu@$publicIp @"
echo '--- Direct container /healthz ---'
curl -s -f http://127.0.0.1:8080/healthz || echo 'FAILED'
echo ''
echo '--- Nginx HTTPS /healthz (SNI berlin-insider.crabdance.com) ---'
curl -k -s -f --resolve berlin-insider.crabdance.com:443:127.0.0.1 https://berlin-insider.crabdance.com/healthz || echo 'FAILED'
echo ''
echo '--- Nginx HTTPS /ui/ (SNI berlin-insider.crabdance.com) ---'
curl -k -s -f -o /dev/null -w '%{http_code}' --resolve berlin-insider.crabdance.com:443:127.0.0.1 https://berlin-insider.crabdance.com/ui/
"@

Write-Host "Endpoint test results:`n$httpTests"
if ($httpTests -match "200") {
    Write-Host "  [PASS] Berlin Insider /ui/ returned HTTP 200." -ForegroundColor Green
} else {
    throw "Berlin Insider endpoint validation failed."
}

Write-Host "`n==========================================" -ForegroundColor Green
Write-Host "  ALL VALIDATION CHECKS PASSED!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

