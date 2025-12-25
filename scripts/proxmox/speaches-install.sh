#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Blake (harms-haus)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/harms-haus/speaches

set -e
set -o pipefail

# Setup colors
YW=$(echo "\033[33m")
BL=$(echo "\033[34m")
HA=$(echo "\033[1;34m")
GN=$(echo "\033[32m")
RD=$(echo "\033[31m")
CL=$(echo "\033[m")
BGN=$(echo "\033[4;32m")
CREATING=$(echo "\033[1;32m")
TAB=$(echo "\t")

# Helper functions
msg_info() { echo -e "${BL}[INFO]${CL} $1"; }
msg_ok() { echo -e "${GN}[OK]${CL} $1"; }
msg_error() { echo -e "${RD}[ERROR]${CL} $1"; }

msg_info "Setting up Speaches dependencies..."

# Install system dependencies
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  ffmpeg \
  git \
  build-essential \
  libgl1 \
  libglib2.0-0 \
  libgomp1

# Install uv
if ! command -v uv &> /dev/null; then
    msg_info "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    source $HOME/.cargo/env || true
    # Add to path for current session if not already there
    export PATH="$HOME/.local/bin:$PATH"
fi

# Clone repository
INSTALL_DIR="/opt/speaches"
if [ ! -d "$INSTALL_DIR" ]; then
    msg_info "Cloning Speaches repository..."
    git clone https://github.com/harms-haus/speaches.git "$INSTALL_DIR"
else
    msg_info "Speaches repository already exists, skipping clone."
fi

cd "$INSTALL_DIR"

# Install Python 3.12 if not present (Ubuntu 24.04 has it, but just in case)
msg_info "Setting up Python environment..."
uv python install 3.12

# Sync dependencies
msg_info "Syncing dependencies with uv..."
uv sync --frozen --no-dev

# Create cache directory
mkdir -p /root/.cache/huggingface/hub

# Create systemd service
msg_info "Creating systemd service..."
cat <<EOF >/etc/systemd/system/speaches.service
[Unit]
Description=Speaches Service
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
Environment="UVICORN_HOST=0.0.0.0"
Environment="UVICORN_PORT=8000"
Environment="PATH=${INSTALL_DIR}/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=${INSTALL_DIR}/.venv/bin/uvicorn --factory speaches.main:create_app
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now speaches

msg_ok "Speaches has been installed and started!"

