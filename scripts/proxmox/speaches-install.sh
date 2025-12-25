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
  jq \
  libgl1 \
  libglib2.0-0 \
  libgomp1

# Install uv
if ! command -v uv &> /dev/null; then
    msg_info "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# Ensure uv and uvx are in PATH
export PATH="/root/.local/bin:$PATH"

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
uv sync --no-dev

# Optional: Install CUDA libraries if GPU is detected
if command -v nvidia-smi &> /dev/null; then
    msg_info "GPU detected, installing additional CUDA libraries for faster-whisper and Kokoro (ONNX Runtime)..."
    uv pip install \
        nvidia-cublas-cu12 \
        nvidia-cudnn-cu12 \
        nvidia-cuda-runtime-cu12 \
        nvidia-cuda-cupti-cu12 \
        nvidia-cuda-nvrtc-cu12 \
        nvidia-nvtx-cu12 \
        nvidia-cuda-nvjitlink-cu12 \
        nvidia-cusparse-cu12 \
        nvidia-curand-cu12 \
        nvidia-cusolver-cu12
fi

# Create cache directory
mkdir -p /root/.cache/huggingface/hub

# Copy model manager script
msg_info "Installing model management script..."
cat > /usr/local/bin/speaches-models << 'MODEL_EOF'
#!/bin/bash
SPEACHES_BASE_URL="${SPEACHES_BASE_URL:-http://localhost:8000}"

check_server() {
    curl -s --max-time 5 "$SPEACHES_BASE_URL/health" >/dev/null 2>&1 || {
        echo "ERROR: Cannot connect to Speaches server at $SPEACHES_BASE_URL"
        exit 1
    }
}

case "$1" in
    ls-remote)
        check_server
        echo "Available models:"
        curl -s "$SPEACHES_BASE_URL/v1/registry" | jq -r '.data[] | "\(.id) (\(.task))"' 2>/dev/null || echo "Install jq: apt-get install jq"
        ;;
    ls-stt)
        check_server
        echo "STT models:"
        curl -s "$SPEACHES_BASE_URL/v1/registry?task=automatic-speech-recognition" | jq -r '.data[] | "\(.id)"' 2>/dev/null || echo "Install jq: apt-get install jq"
        ;;
    ls-tts)
        check_server
        echo "TTS models:"
        curl -s "$SPEACHES_BASE_URL/v1/registry?task=text-to-speech" | jq -r '.data[] | "\(.id)"' 2>/dev/null || echo "Install jq: apt-get install jq"
        ;;
    download)
        check_server
        [ -z "$2" ] && echo "Usage: speaches-models download <model_id>" && exit 1
        echo "Downloading $2..."
        response=$(curl -s -w "\n%{http_code}" -X POST "$SPEACHES_BASE_URL/v1/models/$2")
        status=$(echo "$response" | tail -n1)
        if [ "$status" = "200" ]; then
            echo "SUCCESS: Model downloaded"
        elif [ "$status" = "201" ]; then
            echo "WARNING: Model already exists"
        else
            echo "ERROR: Failed to download (HTTP $status)"
        fi
        ;;
    ls)
        check_server
        echo "Downloaded models:"
        curl -s "$SPEACHES_BASE_URL/v1/models" | jq -r '.data[] | "\(.id) (\(.task))"' 2>/dev/null || echo "Install jq: apt-get install jq"
        ;;
    rm)
        check_server
        [ -z "$2" ] && echo "Usage: speaches-models rm <model_id>" && exit 1
        echo "Deleting $2..."
        status=$(curl -s -w "%{http_code}" -X DELETE "$SPEACHES_BASE_URL/v1/models/$2")
        if [ "$status" = "200" ]; then
            echo "SUCCESS: Model deleted"
        else
            echo "ERROR: Failed to delete (HTTP $status)"
        fi
        ;;
    *)
        echo "Speaches Model Manager"
        echo ""
        echo "Usage: speaches-models <command> [model_id]"
        echo ""
        echo "Commands:"
        echo "  ls-remote          List all available models"
        echo "  ls-stt            List speech-to-text models"
        echo "  ls-tts            List text-to-speech models"
        echo "  download <model>   Download a model"
        echo "  ls                 List downloaded models"
        echo "  rm <model>         Delete a model"
        echo ""
        echo "Examples:"
        echo "  speaches-models ls-remote"
        echo "  speaches-models download whisper-1"
        echo "  speaches-models ls"
        ;;
esac
MODEL_EOF
chmod +x /usr/local/bin/speaches-models

# Create systemd service
msg_info "Creating systemd service..."
# Detect if we should add LD_LIBRARY_PATH for NVIDIA libraries
LD_LIBRARY_PATH_ENV=""
if command -v nvidia-smi &> /dev/null; then
    # Construct LD_LIBRARY_PATH with all potential NVIDIA library locations
    NVIDIA_LIBS=""
    # Note: package names like nvidia-cublas-cu12 often map to directory names like nvidia/cublas
    for lib in cublas cudnn cuda_runtime cuda_cupti cuda_nvrtc nvtx cuda_nvjitlink cusparse curand cusolver; do
        LIB_PATH="${INSTALL_DIR}/.venv/lib/python3.12/site-packages/nvidia/${lib}/lib"
        if [ -d "$LIB_PATH" ]; then
            if [ -z "$NVIDIA_LIBS" ]; then
                NVIDIA_LIBS="$LIB_PATH"
            else
                NVIDIA_LIBS="$NVIDIA_LIBS:$LIB_PATH"
            fi
        fi
    done
    if [ -n "$NVIDIA_LIBS" ]; then
        LD_LIBRARY_PATH_ENV="Environment=\"LD_LIBRARY_PATH=$NVIDIA_LIBS\""
    fi
fi

cat <<EOF >/etc/systemd/system/speaches.service
[Unit]
Description=Speaches Service
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
Environment="UVICORN_HOST=0.0.0.0"
Environment="UVICORN_PORT=8000"
${LD_LIBRARY_PATH_ENV}
# Uncomment the line below to force CUDA usage for Whisper. Default is "auto".
# Environment="WHISPER__INFERENCE_DEVICE=cuda"
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
msg_info "Use 'speaches-models' command to manage models"
msg_info "Example: speaches-models ls-remote"

