# setup-infra

This repository bootstraps and configures Linux servers with a single one-liner entrypoint plus one main Ansible playbook.

## Files

- `bootstrap.sh`  
  Unified entrypoint script:
  - `full` mode (default): first-touch bootstrap + runs full `server-setup.yml` locally on the VM.
  - `bootstrap-only` mode: only creates `ubuntu` user + SSH key access and basic dependencies.

- `server-setup.yml`  
  Main playbook for:
  - `ubuntu` user baseline (user, sudoers, authorized key)
  - package updates and core dependencies
  - swap file setup
  - Docker installation (conditional)
  - Tailscale installation and join
  - UFW hardening
  - optional SSH mesh config deployment

- `secrets.yml`  
  Encrypted vault values (for example `tailscale_auth_key`).

- `ansible_master.pub`  
  Universal public key distributed to managed hosts.

## Usage

### 1) Fresh VM full setup with one-liner (recommended)

This installs dependencies, sets up SSH key auth, prompts for vault password, and applies full `server-setup.yml` on that VM.

```bash
curl -fsSL https://raw.githubusercontent.com/diligentapple/setup-infra/main/bootstrap.sh | bash
```

### 2) Bootstrap-only mode (no full playbook run)

```bash
curl -fsSL https://raw.githubusercontent.com/diligentapple/setup-infra/main/bootstrap.sh | bash -s -- bootstrap-only
```

## Security notes

- Vault password handling uses a secure temp file and cleanup trap.
- `tailscale up --authkey=...` task is marked `no_log: true`.
- SSH mesh template deploy is optional (`deploy_mesh_ssh_config: false` by default) and only runs when template exists.

## Validation

```bash
bash -n bootstrap.sh
ansible-playbook --syntax-check server-setup.yml
```
