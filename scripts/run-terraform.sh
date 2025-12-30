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
            $DOCKER_COMPOSE_CMD run --rm terraform "$cmd" "$@"
            ;;
        "help"|"-h"|"--help")
            $DOCKER_COMPOSE_CMD run --rm terraform help
            ;;
        "")
            echo "Error: No command specified"
            echo "Usage: $0 <terraform_command> [options]"
            echo "Available commands: init, plan, apply, destroy, validate, fmt, show, output, import, state, taint, untaint, force-unlock, workspace, version"
            exit 1
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

# Run the terraform command
run_terraform "$@"
