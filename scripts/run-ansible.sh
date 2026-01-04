#!/bin/bash

# Ansible container runner script
# Usage: ./scripts/run-ansible.sh [ansible_command] [options]

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

# Function to run ansible command
run_ansible() {
    local cmd="$1"
    shift
    
    case "$cmd" in
        "--version")
            echo "Running: ansible --version"
            $DOCKER_COMPOSE_CMD run --rm ansible ansible --version --help | head -5
            ;;
        "playbook"|"play")
            echo "Running: ansible-playbook $@"
            $DOCKER_COMPOSE_CMD run --rm ansible ansible-playbook "$@"
            ;;
        "inventory"|"inv")
            echo "Running: ansible-inventory $@"
            $DOCKER_COMPOSE_CMD run --rm ansible ansible-inventory "$@"
            ;;
        "config")
            echo "Running: ansible-config $@"
            $DOCKER_COMPOSE_CMD run --rm ansible ansible-config "$@"
            ;;
        "vault")
            echo "Running: ansible-vault $@"
            $DOCKER_COMPOSE_CMD run --rm ansible ansible-vault "$@"
            ;;
        "console")
            echo "Running: ansible-console $@"
            $DOCKER_COMPOSE_CMD run --rm ansible ansible-console "$@"
            ;;
        "doc")
            echo "Running: ansible-doc $@"
            $DOCKER_COMPOSE_CMD run --rm ansible ansible-doc "$@"
            ;;
        "galaxy")
            echo "Running: ansible-galaxy $@"
            $DOCKER_COMPOSE_CMD run --rm ansible ansible-galaxy "$@"
            ;;
        "help"|"-h"|"--help")
            $DOCKER_COMPOSE_CMD run --rm ansible ansible --help
            ;;
        "")
            echo "Error: No command specified"
            echo "Usage: $0 <ansible_command> [options]"
            echo "Available commands: playbook, inventory, vault, config, console, doc, galaxy, --version"
            echo "Aliases: play, inv"
            exit 1
            ;;
        *)
            echo "Running: ansible $@"
            $DOCKER_COMPOSE_CMD run --rm ansible ansible "$@"
            ;;
    esac
}

# Change to project root
cd "$PROJECT_ROOT"

# Run the ansible command
run_ansible "$@"
