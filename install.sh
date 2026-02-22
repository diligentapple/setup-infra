#!/bin/bash
set -e

# --- CONFIG ---
REPO_URL="https://github.com/diligentapple/setup-infra.git"
CLONE_DIR="/tmp/ansible-setup"
# --------------

echo "🚀 Starting Self-Setup..."

# 1. Install Ansible (Ubuntu/Debian)
if ! command -v ansible &> /dev/null; then
    echo "📦 Installing Ansible..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq ansible git
fi

# 2. Clone your Repository
echo "⬇️  Downloading Configuration..."
rm -rf "$CLONE_DIR"
git clone "$REPO_URL" "$CLONE_DIR"
cd "$CLONE_DIR"

# 3. Handle Vault Password
# We need the password to decrypt secrets.yml (Tailscale keys)
echo "----------------------------------------------------"
echo "🔐 Enter your Ansible Vault Password to unlock secrets:"
echo "----------------------------------------------------"
read -s VAULT_PASS
echo "$VAULT_PASS" > .vault_pass

# 4. Run the Playbook (Targeting Localhost)
echo "⚙️  Running Ansible..."
# -i "localhost," tells Ansible to run on this machine
# -c local tells Ansible not to use SSH, just run commands directly
sudo ansible-playbook \
    -i "localhost," \
    -c local \
    server-setup.yml \
    --vault-password-file .vault_pass \
    --extra-vars "target_user=$(whoami)"

# 5. Cleanup (Security)
echo "🧹 Cleaning up..."
rm .vault_pass
cd ~
rm -rf "$CLONE_DIR"

echo "✅ Server Setup Complete!"
