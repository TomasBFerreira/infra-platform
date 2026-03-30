#!/bin/bash

# Terraform container runner script
# Usage: ./scripts/run-terraform.sh [terraform_command] [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Determine execution mode: Docker (preferred) or direct terraform binary fallback
USE_DIRECT_TERRAFORM=false
DOCKER_COMPOSE_CMD=""

if command -v docker-compose &> /dev/null || docker compose version &> /dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
    if docker compose version &> /dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
    fi
elif command -v terraform &> /dev/null; then
    USE_DIRECT_TERRAFORM=true
    echo "Docker not available — using direct terraform binary: $(terraform version | head -1)"
else
    echo "Error: neither Docker nor a terraform binary is available"
    exit 1
fi

# Function to run terraform command
run_terraform() {
    local cmd="$1"
    shift

    case "$cmd" in
        "init"|"plan"|"apply"|"destroy"|"validate"|"fmt"|"show"|"output"|"import"|"state"|"taint"|"untaint"|"force-unlock"|"workspace"|"version")
            echo "Running: terraform $cmd $@"
            if [ "$USE_DIRECT_TERRAFORM" = "true" ]; then
                terraform "$cmd" "$@"
            else
                $DOCKER_COMPOSE_CMD run --rm -e TF_VAR_proxmox_api_url -e TF_VAR_proxmox_user -e TF_VAR_proxmox_password -e TF_VAR_vault_token -e TF_VAR_vault_address -e VAULT_ADDR -e TF_VAR_pve_api -e TF_VAR_pve_user -e TF_VAR_pve_pass -e TF_VAR_ssh_user -e TF_VAR_vmid -e TF_VAR_ip_address -e TF_VAR_vm_hostname -e TF_VAR_target_node -e TF_VAR_template_vmid -e TF_VAR_network_bridge -e TF_VAR_gateway -e TF_VAR_vm_cores -e TF_VAR_vm_memory_mb -e TF_VAR_vm_disk_gb terraform "$cmd" "$@"
            fi
            ;;
        "help"|"-h"|"--help")
            if [ "$USE_DIRECT_TERRAFORM" = "true" ]; then
                terraform help
            else
                $DOCKER_COMPOSE_CMD run --rm terraform help
            fi
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
            if [ "$USE_DIRECT_TERRAFORM" = "true" ]; then
                (cd "$PROJECT_ROOT/$chdir" && terraform "$cmd" "$@")
            else
                $DOCKER_COMPOSE_CMD run --rm -w "/workspace/$chdir" -e TF_VAR_proxmox_api_url -e TF_VAR_proxmox_user -e TF_VAR_proxmox_password -e TF_VAR_vault_token -e TF_VAR_vault_address -e VAULT_ADDR -e TF_VAR_pve_api -e TF_VAR_pve_user -e TF_VAR_pve_pass -e TF_VAR_ssh_user -e TF_VAR_vmid -e TF_VAR_ip_address -e TF_VAR_vm_hostname -e TF_VAR_target_node -e TF_VAR_template_vmid -e TF_VAR_network_bridge -e TF_VAR_gateway -e TF_VAR_vm_cores -e TF_VAR_vm_memory_mb -e TF_VAR_vm_disk_gb terraform "$cmd" "$@"
            fi
            ;;
        "help"|"-h"|"--help")
            if [ "$USE_DIRECT_TERRAFORM" = "true" ]; then
                terraform help
            else
                $DOCKER_COMPOSE_CMD run --rm terraform help
            fi
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

# Use Vault address from environment (TF_VAR_vault_address set by workflow)

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
