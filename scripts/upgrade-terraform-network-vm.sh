#!/bin/bash
set -e

cd /app/dev/infra-platform

# Upgrade Terraform providers for network-vm
./scripts/run-terraform.sh -chdir terraform/dev/network-vm init -upgrade
