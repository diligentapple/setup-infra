# setup-infra

This repository bootstraps and configures Linux servers with a single one-liner entrypoint plus one main Ansible playbook.

## Files

- `bootstrap.sh`
  Unified entrypoint script:
  - `full` mode (default): first-touch bootstrap + runs full `server-setup.yml` locally on the VM.
  - `bootstrap-only` mode: only creates `ubuntu` user + SSH key access and basic dependencies (`python3`, `python3-pip`, `git`, `curl`, `nano`).

- `server-setup.yml`
  Main playbook for:
  - `ubuntu` user baseline (user, sudoers, authorized key)
  - package updates and core dependencies
  - swap file setup (configurable size, default 2G)
  - Docker installation (optional)
  - Tailscale installation and join (optional)
  - Extra packages (configurable)
  - UFW hardening

- `secrets.yml`
  Encrypted vault values (for example `tailscale_auth_key`).

- `ansible_master.pub`
  Universal public key distributed to managed hosts.

## Usage

### 1) Fresh VM full setup with one-liner (recommended)

This installs dependencies, sets up SSH key auth, prompts for vault password, asks whether to install Docker/Tailscale, asks swap size in GB, and applies full `server-setup.yml` on that VM.

```bash
curl -fsSL https://raw.githubusercontent.com/diligentapple/setup-infra/main/bootstrap.sh | bash
```

### 2) Bootstrap-only mode (no full playbook run)

```bash
curl -fsSL https://raw.githubusercontent.com/diligentapple/setup-infra/main/bootstrap.sh | bash -s -- bootstrap-only
```

### 3) Install extra packages via the one-liner

Pass the `EXTRA_PACKAGES` environment variable (space-separated) to install additional
apt packages alongside the defaults:

```bash
EXTRA_PACKAGES="nginx redis-server postgresql" curl -fsSL https://raw.githubusercontent.com/diligentapple/setup-infra/main/bootstrap.sh | bash
```

If you don't set the env var, the script will prompt you interactively during setup.

## Adding packages permanently

To make extra packages part of every deployment, edit the top of `bootstrap.sh`:

```bash
EXTRA_PACKAGES="${EXTRA_PACKAGES:-nginx redis-server}"
```

Or add them directly to the `extra_packages` list in `server-setup.yml`:

```yaml
vars:
  extra_packages:
    - nginx
    - redis-server
```

## Step-by-step after running the one-liner

After the one-liner finishes on your VM, follow this process from your local machine.

### Step 1: Ensure your private key matches `ansible_master.pub`

The server trusts the public key from this repo. Your local key pair must match it.

Check your local public key fingerprint:

```bash
ssh-keygen -lf ~/.ssh/your_key.pub
```

### Step 2: Add the server to local `~/.ssh/config`

Edit your local SSH config:

```bash
nano ~/.ssh/config
```

Add an entry:

```sshconfig
Host my-new-vm
  HostName <SERVER_PUBLIC_IP>
  User ubuntu
  IdentityFile ~/.ssh/your_key
  IdentitiesOnly yes
```

Save and lock permissions:

```bash
chmod 600 ~/.ssh/config
```

### Step 3: Test SSH access

```bash
ssh my-new-vm
```

On first connection, accept host key prompt (`yes`) after verifying fingerprint.

### Step 4: Verify key baseline services on server

Once logged in:

```bash
whoami
sudo -n true && echo "sudo ok"
swapon --show
ufw status
```

If Docker was enabled during prompt:

```bash
docker --version
```

If Tailscale was enabled during prompt:

```bash
tailscale status
```

### Step 5: Re-run provisioning (optional)

If you want to re-apply configuration later:

```bash
curl -fsSL https://raw.githubusercontent.com/diligentapple/setup-infra/main/bootstrap.sh | bash
```

Or bootstrap only:

```bash
curl -fsSL https://raw.githubusercontent.com/diligentapple/setup-infra/main/bootstrap.sh | bash -s -- bootstrap-only
```

## Security notes

- Vault password handling uses a secure temp file and cleanup trap.
- `tailscale up --authkey=...` task is marked `no_log: true`.
- GPG keys are stored in `/etc/apt/keyrings/` using `signed-by` (modern approach).

## Validation

```bash
bash -n bootstrap.sh
ansible-playbook --syntax-check server-setup.yml
```
