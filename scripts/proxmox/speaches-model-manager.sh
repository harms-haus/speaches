#!/usr/bin/env bash

# Speaches Model Manager for LXC containers
# Simple script to manage models without requiring the CLI tool

set -e

SPEACHES_BASE_URL="${SPEACHES_BASE_URL:-http://localhost:8000}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_server() {
    if ! curl -s --max-time 5 "$SPEACHES_BASE_URL/health" >/dev/null 2>&1; then
        log_error "Cannot connect to Speaches server at $SPEACHES_BASE_URL"
        log_error "Make sure the server is running and SPEACHES_BASE_URL is set correctly"
        exit 1
    fi
}

list_available_models() {
    log_info "Fetching available models from registry..."
    local task_filter=""
    if [ -n "$1" ]; then
        task_filter="?task=$1"
    fi

    curl -s "$SPEACHES_BASE_URL/v1/registry$task_filter" | jq -r '.data[] | "\(.id) (\(.task))"' 2>/dev/null || {
        log_error "Failed to fetch models. Is jq installed?"
        exit 1
    }
}

download_model() {
    local model_id="$1"
    if [ -z "$model_id" ]; then
        log_error "Please specify a model ID to download"
        echo "Usage: $0 download <model_id>"
        exit 1
    fi

    log_info "Downloading model: $model_id"
    local response
    response=$(curl -s -w "\n%{http_code}" -X POST "$SPEACHES_BASE_URL/v1/models/$model_id")

    local status_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n -1)

    if [ "$status_code" = "200" ]; then
        log_success "Model '$model_id' downloaded successfully"
    elif [ "$status_code" = "201" ]; then
        log_warn "Model '$model_id' already exists"
    else
        log_error "Failed to download model '$model_id' (HTTP $status_code)"
        echo "Response: $body"
        exit 1
    fi
}

list_downloaded_models() {
    log_info "Listing downloaded models..."
    curl -s "$SPEACHES_BASE_URL/v1/models" | jq -r '.data[] | "\(.id) (\(.task))"' 2>/dev/null || {
        log_error "Failed to list downloaded models"
        exit 1
    }
}

delete_model() {
    local model_id="$1"
    if [ -z "$model_id" ]; then
        log_error "Please specify a model ID to delete"
        echo "Usage: $0 delete <model_id>"
        exit 1
    fi

    log_info "Deleting model: $model_id"
    local response
    response=$(curl -s -w "\n%{http_code}" -X DELETE "$SPEACHES_BASE_URL/v1/models/$model_id")

    local status_code=$(echo "$response" | tail -n1)

    if [ "$status_code" = "200" ]; then
        log_success "Model '$model_id' deleted successfully"
    else
        log_error "Failed to delete model '$model_id' (HTTP $status_code)"
        exit 1
    fi
}

show_usage() {
    cat << EOF
Speaches Model Manager

USAGE:
    $0 <COMMAND> [OPTIONS]

COMMANDS:
    list-available, ls-remote    List all available models in the registry
    list-stt, ls-stt             List available speech-to-text models
    list-tts, ls-tts             List available text-to-speech models
    download, dl <model_id>      Download a specific model
    list-downloaded, ls          List downloaded models
    delete, rm <model_id>        Delete a downloaded model

EXAMPLES:
    $0 ls-remote                    # List all available models
    $0 ls-stt                       # List STT models only
    $0 download whisper-1           # Download whisper-1 model
    $0 ls                           # List downloaded models
    $0 rm whisper-1                 # Delete whisper-1 model

ENVIRONMENT VARIABLES:
    SPEACHES_BASE_URL               Server URL (default: http://localhost:8000)

EOF
}

main() {
    check_server

    case "$1" in
        "list-available"|"ls-remote")
            list_available_models
            ;;
        "list-stt"|"ls-stt")
            list_available_models "automatic-speech-recognition"
            ;;
        "list-tts"|"ls-tts")
            list_available_models "text-to-speech"
            ;;
        "download"|"dl")
            download_model "$2"
            ;;
        "list-downloaded"|"ls")
            list_downloaded_models
            ;;
        "delete"|"rm")
            delete_model "$2"
            ;;
        "help"|"-h"|"--help"|"")
            show_usage
            ;;
        *)
            log_error "Unknown command: $1"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
