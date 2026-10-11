# OCI Apps Deployment

Terraform and automated deployment pipeline for running containerized apps on Oracle Cloud Infrastructure (OCI) Always Free tier. The apps live in their own Git repositories; local checkouts under `apps/` are gitignored.

## Architecture

- **Host**: Single `VM.Standard.A1.Flex` instance running Canonical Ubuntu 24.04 ARM64.
- **Compute Sizing**: 1 OCPU, 6 GB RAM, 50 GB Boot Volume (€0 / Always Free).
- **Public Ingress**:
  - `TCP 22`: SSH management
  - `TCP 80`: HTTP (redirects to HTTPS)
  - `TCP 443`: HTTPS (app web UI & Telegram webhook)
- **Services**:
  - App containers: one Docker Compose service per app repo, bound to `127.0.0.1`, with persistent data on the host.
  - `nginx`: Host reverse proxy terminating SSL and routing traffic to `127.0.0.1:8080`.
  - `oci-apps-update.timer`: systemd timer polling `main` on each app repo every 5 minutes; fast-forwards and rebuilds on new commits.

## Quick Start

### 1. Prerequisites
- Terraform >= 1.5
- OCI CLI credentials configured in `~/.oci/config`
- PowerShell 7+

### 2. Deploy
```powershell
.\scripts\deploy.ps1
```

### 3. Validate
```powershell
.\scripts\validate.ps1
```

### 4. Diagnose
```powershell
.\scripts\diagnose.ps1
```

### 5. Install/Reinstall Auto-Update Timer
```powershell
.\scripts\install-auto-update.ps1
```
Safe to run standalone on a live host — does not touch `.env`/`.data`/`.runtime`. Logs: `journalctl -u oci-apps-update`.

### 6. Destroy
```powershell
.\scripts\destroy.ps1
```

