# OCI Apps Deployment: Article-to-Speech & Berlin Insider

Terraform and automated deployment pipeline for running **Article to Speech** and **Berlin Insider** on Oracle Cloud Infrastructure (OCI) Always Free tier.

## Architecture

- **Host**: Single `VM.Standard.A1.Flex` instance running Canonical Ubuntu 24.04 ARM64.
- **Compute Sizing**: 1 OCPU, 6 GB RAM, 50 GB Boot Volume (€0 / Always Free).
- **Public Ingress**:
  - `TCP 22`: SSH management
  - `TCP 80`: HTTP (redirects to HTTPS)
  - `TCP 443`: HTTPS (Berlin Insider UI & Telegram Webhook)
- **Services**:
  - `article-to-speech`: Docker Compose container running in long-polling mode with persistent audio artifacts.
  - `berlin-insider`: Docker Compose container exposing internal port 8080 with Playwright Chromium and persistent SQLite database.
  - `nginx`: Host reverse proxy terminating SSL (`berlin-insider.crabdance.com`) and routing traffic to `127.0.0.1:8080`.
  - `oci-apps-update.timer`: systemd timer polling `main` on both repos every 5 minutes; fast-forwards and rebuilds on new commits.

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

