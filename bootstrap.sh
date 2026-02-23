#!/bin/bash
set -euo pipefail

# ===================================================================
# CONFIGURATION — edit these before deploying, or override via env vars
# ===================================================================
GITHUB_USER="diligentapple"
REPO_NAME="setup-infra"
KEY_URL="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/main/ansible_master.pub"
REPO_URL="https://github.com/$GITHUB_USER/$REPO_NAME.git"
CLONE_DIR="/tmp/ansible-setup"

# Extra packages to install via the Ansible playbook (space-separated).
# Override with the EXTRA_PACKAGES env var, e.g.:
#   EXTRA_PACKAGES="nginx redis-server" curl -fsSL ... | bash
EXTRA_PACKAGES="${EXTRA_PACKAGES:-}"
# ===================================================================

install_base_deps() {
  echo ">>> Installing base dependencies..."
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq python3 python3-pip git curl nano
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y python3 python3-pip git curl nano
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
  # The Ansible playbook uses apt modules — require a Debian-based distro.
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "ERROR: Full server setup requires a Debian/Ubuntu system (apt-get not found)." >&2
    exit 1
  fi

  echo ">>> Preparing full server setup from Ansible playbook..."
  install_ansible

  # When piped through curl, stdin is the script itself.
  # Redirect interactive reads from /dev/tty so prompts work.
  read -rp ">>> Install Docker? [Y/n]: " INSTALL_DOCKER_INPUT < /dev/tty
  read -rp ">>> Install Tailscale? [Y/n]: " INSTALL_TAILSCALE_INPUT < /dev/tty
  read -rp ">>> Swap size in GB [default: 2]: " SWAP_SIZE_INPUT < /dev/tty

  if [ -z "$EXTRA_PACKAGES" ]; then
    read -rp ">>> Extra packages to install (space-separated, or press Enter to skip): " EXTRA_PACKAGES_INPUT < /dev/tty
    EXTRA_PACKAGES="${EXTRA_PACKAGES_INPUT:-}"
  fi

  INSTALL_DOCKER_INPUT=${INSTALL_DOCKER_INPUT:-Y}
  INSTALL_TAILSCALE_INPUT=${INSTALL_TAILSCALE_INPUT:-Y}
  SWAP_SIZE_INPUT=${SWAP_SIZE_INPUT:-2}

  case "$INSTALL_DOCKER_INPUT" in
    [Nn]*) INSTALL_DOCKER=false ;;
    *) INSTALL_DOCKER=true ;;
  esac

  case "$INSTALL_TAILSCALE_INPUT" in
    [Nn]*) INSTALL_TAILSCALE=false ;;
    *) INSTALL_TAILSCALE=true ;;
  esac

  if ! [[ "$SWAP_SIZE_INPUT" =~ ^[0-9]+$ ]] || [ "$SWAP_SIZE_INPUT" -lt 1 ]; then
    echo "Invalid swap size '$SWAP_SIZE_INPUT'. Must be a positive integer (GB)." >&2
    exit 1
  fi

  # Convert space-separated package string into a JSON list for Ansible.
  EXTRA_PKGS_JSON="[]"
  if [ -n "$EXTRA_PACKAGES" ]; then
    EXTRA_PKGS_JSON=$(printf '%s' "$EXTRA_PACKAGES" | tr -s ' ' '\n' | jq -R . | jq -s .)
  fi

  rm -rf "$CLONE_DIR"
  git clone "$REPO_URL" "$CLONE_DIR"
  cd "$CLONE_DIR"

  echo "----------------------------------------------------"
  echo "Enter your Ansible Vault Password to unlock secrets:"
  echo "----------------------------------------------------"
  read -rs VAULT_PASS < /dev/tty

  local vault_file
  vault_file=$(mktemp)
  chmod 600 "$vault_file"
  trap 'rm -f "$vault_file"; rm -rf "$CLONE_DIR"' EXIT
  printf '%s' "$VAULT_PASS" > "$vault_file"

  echo ""
  echo "Running full server-setup.yml on localhost..."
  sudo ansible-playbook \
    -i "localhost," \
    -c local \
    server-setup.yml \
    --vault-password-file "$vault_file" \
    --extra-vars "{\"target_user\":\"ubuntu\",\"install_docker\":${INSTALL_DOCKER},\"install_tailscale\":${INSTALL_TAILSCALE},\"swap_size_gb\":${SWAP_SIZE_INPUT},\"extra_packages\":${EXTRA_PKGS_JSON}}"

  echo "Full server setup complete."
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
