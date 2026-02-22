#!/bin/bash
set -e

# --- CONFIGURATION ---
# This points to the public key we are about to push to GitHub
GITHUB_USER="diligentapple"
REPO_NAME="infra-setup"
KEY_URL="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/main/ansible_master.pub"
# ---------------------

echo ">>> Bootstrapping Server..."

# 1. Install Python & Basic Tools
echo ">>> Installing dependencies..."
if [ -x "$(command -v apt-get)" ]; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq python3 python3-pip git curl
elif [ -x "$(command -v dnf)" ]; then
    sudo dnf install -y python3 python3-pip git curl
fi

# 2. Setup the User (ubuntu)
if ! id "ubuntu" &>/dev/null; then
    echo ">>> Creating 'ubuntu' user..."
    sudo useradd -m -s /bin/bash -G sudo ubuntu
    # Enable passwordless sudo
    echo "ubuntu ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ubuntu
fi

# 3. Download and Authorize Key
echo ">>> Fetching SSH Key from GitHub..."
sudo mkdir -p /home/ubuntu/.ssh
sudo chmod 700 /home/ubuntu/.ssh

# Download the key and append it to authorized_keys
curl -sL "$KEY_URL" | sudo tee -a /home/ubuntu/.ssh/authorized_keys > /dev/null

sudo chmod 600 /home/ubuntu/.ssh/authorized_keys
sudo chown -R ubuntu:ubuntu /home/ubuntu/.ssh

echo ">>> Done! Server configured and accessible via Ansible."
