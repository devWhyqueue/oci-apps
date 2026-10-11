# Agent Guidelines: OCI Apps

This repository contains Terraform and deployment configuration for running containerized apps on an Oracle Cloud Infrastructure (OCI) Always Free ARM compute instance. The apps live in their own Git repositories; local checkouts under `apps/` are gitignored.

## Key Principles & Invariants

1. **€0 / Always Free Guarantee**:
   - VM shape must always be `VM.Standard.A1.Flex` in the tenancy home region (`eu-frankfurt-1`).
   - Resource footprint: 1 OCPU, 6 GB RAM, 50 GB boot volume.
   - Combined with the other instance in the tenancy (1 OCPU, 6 GB RAM), the total tenancy footprint equals exactly 2 OCPUs and 12 GB RAM, complying 100% with Always Free limits.

2. **Security & Exposure**:
   - Only **TCP 22 (SSH)**, **TCP 80 (HTTP)**, and **TCP 443 (HTTPS)** are exposed publicly.
   - Host firewall (`ufw`) blocks all other inbound ports.
   - All applications run as containerized Docker services binding to localhost (`127.0.0.1`).
   - Host Nginx serves as the SSL reverse proxy terminating HTTPS for the web-facing app.
   - `oci-apps-update.timer` polls `main` on each app repo every 5 minutes and rebuilds on fast-forward; no manual redeploy needed for code-only changes.

3. **Secret Management**:
   - Private keys, API tokens (`OPENAI_API_KEY`, `TELEGRAM_BOT_TOKEN`), and service account credentials must never be stored in Git or Terraform state.
   - Secrets are managed in `.env` and `gcp-service-account.json`.

## Common Operations

- **Format & Validate**:
  ```powershell
  terraform -chdir=terraform fmt -check
  terraform -chdir=terraform validate
  ```
- **Plan & Deploy**:
  ```powershell
  .\scripts\deploy.ps1
  ```
- **Validate Deployment**:
  ```powershell
  .\scripts\validate.ps1
  ```
- **Install/Reinstall Auto-Update Timer** (safe on live host, does not touch `.env`/`.data`/`.runtime`):
  ```powershell
  .\scripts\install-auto-update.ps1
  ```
  Logs: `journalctl -u oci-apps-update`.
- **Diagnose**:
  ```powershell
  .\scripts\diagnose.ps1
  ```
- **Destroy**:
  ```powershell
  .\scripts\destroy.ps1
  ```

