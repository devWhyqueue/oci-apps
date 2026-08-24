# scripts/destroy.ps1 - Destroy OCI Apps Infrastructure
[CmdletBinding()]
param(
    [string]$TerraformDir,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$RootDir = Split-Path -Parent $ScriptDir
if (-not $TerraformDir) { $TerraformDir = Join-Path $RootDir "terraform" }

Write-Host "==========================================" -ForegroundColor Red
Write-Host "  Destroy OCI Apps Infrastructure" -ForegroundColor Red
Write-Host "==========================================" -ForegroundColor Red

if (-not $Force) {
    $confirm = Read-Host "Are you sure you want to destroy the OCI Apps instance and networking? (yes/no)"
    if ($confirm -ne "yes") {
        Write-Host "Destruction cancelled." -ForegroundColor Yellow
        return
    }
}

Write-Host "`nRunning Terraform Destroy..." -ForegroundColor Yellow
terraform -chdir="$TerraformDir" destroy -auto-approve

Write-Host "`nInfrastructure destroyed successfully." -ForegroundColor Green
