#!/bin/bash

# Terraform container runner script
# Usage: ./scripts/run-terraform.sh [terraform_command] [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "Error: Docker or Docker Compose is not installed"
    exit 1
fi

# Determine docker compose command
DOCKER_COMPOSE_CMD="docker-compose"
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
fi

# Function to run terraform command
run_terraform() {
    local cmd="$1"
    shift
    
    case "$cmd" in
        "init"|"plan"|"apply"|"destroy"|"validate"|"fmt"|"show"|"output"|"import"|"state"|"taint"|"untaint"|"force-unlock"|"workspace"|"version")
            echo "Running: terraform $cmd $@"
            $DOCKER_COMPOSE_CMD run --rm -e TF_VAR_proxmox_api_url -e TF_VAR_proxmox_user -e TF_VAR_proxmox_password -e TF_VAR_vault_token -e TF_VAR_vault_address -e VAULT_ADDR -e TF_VAR_pve_api -e TF_VAR_pve_user -e TF_VAR_pve_pass -e TF_VAR_ssh_user terraform "$cmd" "$@"
            ;;
        "help"|"-h"|"--help")
            $DOCKER_COMPOSE_CMD run --rm terraform help
            ;;
        *)
            echo "Error: Unknown terraform command '$cmd'"
            echo "Run '$0 help' for available commands"
            exit 1
            ;;
    esac
}

# Function to run terraform command with directory
run_terraform_with_chdir() {
    local chdir="$1"
    local cmd="$2"
    shift 2
    
    case "$cmd" in
        "init"|"plan"|"apply"|"destroy"|"validate"|"fmt"|"show"|"output"|"import"|"state"|"taint"|"untaint"|"force-unlock"|"workspace"|"version")
            echo "Running: terraform $cmd $@ (in directory: $chdir)"
            $DOCKER_COMPOSE_CMD run --rm -w "/workspace/$chdir" -e TF_VAR_proxmox_api_url -e TF_VAR_proxmox_user -e TF_VAR_proxmox_password -e TF_VAR_vault_token -e TF_VAR_vault_address -e VAULT_ADDR -e TF_VAR_pve_api -e TF_VAR_pve_user -e TF_VAR_pve_pass -e TF_VAR_ssh_user terraform "$cmd" "$@"
            ;;
        "help"|"-h"|"--help")
            $DOCKER_COMPOSE_CMD run --rm terraform help
            ;;
        *)
            echo "Error: Unknown terraform command '$cmd'"
            echo "Run '$0 help' for available commands"
            exit 1
            ;;
    esac
}

# Change to project root
cd "$PROJECT_ROOT"

# Set environment variables for Vault and Proxmox
if [ -f ".env" ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Override Vault address for containers
export TF_VAR_vault_address="http://host.docker.internal:8200"
export VAULT_ADDR="http://host.docker.internal:8200"

# Check for -chdir flag first
CHDIR_DIR=""
ARGS=()

# Parse arguments properly
while [[ $# -gt 0 ]]; do
    case $1 in
        -chdir)
            CHDIR_DIR="$2"
            shift 2
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done

# Run the terraform command
if [ -n "$CHDIR_DIR" ]; then
    run_terraform_with_chdir "$CHDIR_DIR" "${ARGS[@]}"
else
    run_terraform "${ARGS[@]}"
fi
