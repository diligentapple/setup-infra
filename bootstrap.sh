#!/bin/bash
set -euo pipefail

# --- CONFIGURATION ---
GITHUB_USER="diligentapple"
REPO_NAME="setup-infra"
KEY_URL="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/main/ansible_master.pub"
REPO_URL="https://github.com/$GITHUB_USER/$REPO_NAME.git"
CLONE_DIR="/tmp/ansible-setup"
# ---------------------

install_base_deps() {
  echo ">>> Installing base dependencies..."
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq python3 python3-pip git curl
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y python3 python3-pip git curl
  else
    echo "No supported package manager found (apt-get/dnf)." >&2
    exit 1
  fi
}

install_ansible() {
  if command -v ansible-playbook >/dev/null 2>&1; then
    return
  fi

  echo ">>> Installing Ansible..."
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq ansible
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y ansible
  else
    echo "Cannot install Ansible: no supported package manager found." >&2
    exit 1
  fi
}

bootstrap_remote() {
  echo ">>> Bootstrapping Server..."
  install_base_deps

  if ! id "ubuntu" &>/dev/null; then
    echo ">>> Creating 'ubuntu' user..."
    sudo useradd -m -s /bin/bash -G sudo ubuntu
  fi

  echo "ubuntu ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ubuntu >/dev/null
  sudo chmod 0440 /etc/sudoers.d/ubuntu

  echo ">>> Fetching SSH Key from GitHub..."
  sudo mkdir -p /home/ubuntu/.ssh
  sudo chmod 700 /home/ubuntu/.ssh
  sudo touch /home/ubuntu/.ssh/authorized_keys

  local tmp_key
  tmp_key=$(mktemp)
  trap 'rm -f "$tmp_key"' RETURN
  curl -fsSL "$KEY_URL" > "$tmp_key"

  if ! sudo grep -qxF "$(cat "$tmp_key")" /home/ubuntu/.ssh/authorized_keys; then
    sudo sh -c "cat '$tmp_key' >> /home/ubuntu/.ssh/authorized_keys"
  fi

  sudo chmod 600 /home/ubuntu/.ssh/authorized_keys
  sudo chown -R ubuntu:ubuntu /home/ubuntu/.ssh
}

run_full_server_setup() {
  echo ">>> Preparing full server setup from Ansible playbook..."
  install_ansible

  rm -rf "$CLONE_DIR"
  git clone "$REPO_URL" "$CLONE_DIR"
  cd "$CLONE_DIR"

  echo "----------------------------------------------------"
  echo "🔐 Enter your Ansible Vault Password to unlock secrets:"
  echo "----------------------------------------------------"
  read -rs VAULT_PASS

  local vault_file
  vault_file=$(mktemp)
  chmod 600 "$vault_file"
  trap 'rm -f "$vault_file"; rm -rf "$CLONE_DIR"' EXIT
  printf '%s' "$VAULT_PASS" > "$vault_file"

  echo "⚙️  Running full server-setup.yml on localhost..."
  sudo ansible-playbook \
    -i "localhost," \
    -c local \
    server-setup.yml \
    --vault-password-file "$vault_file" \
    --extra-vars "target_user=ubuntu"

  echo "✅ Full server setup complete."
}

MODE="${1:-full}"
case "$MODE" in
  full)
    bootstrap_remote
    run_full_server_setup
    ;;
  bootstrap-only)
    bootstrap_remote
    echo ">>> Bootstrap-only mode complete."
    ;;
  *)
    echo "Usage: $0 [full|bootstrap-only]"
    exit 1
    ;;
esac
