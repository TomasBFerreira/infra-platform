#!/bin/bash

# Simple test to check if containers can reach Vault
echo "Testing container Vault connectivity..."

# Test with a basic container that has curl
docker run --rm --network infra-platform alpine/curl:latest curl -s http://host.docker.internal:8200/v1/sys/health

echo ""
echo "Testing with Terraform container..."
docker compose run --rm terraform sh -c "curl -s http://host.docker.internal:8200/v1/sys/health"
