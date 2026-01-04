#!/bin/bash

# Simple test to check if containers can reach Vault
echo "Testing container Vault connectivity..."

# Test with a basic container that has curl
docker run --rm --network infra-platform_infra-network alpine/curl:latest curl -s http://192.168.50.202:8200/v1/sys/health

echo ""
echo "Testing with Terraform container..."
docker compose run --rm --entrypoint bash terraform -c "curl -s http://192.168.50.202:8200/v1/sys/health"
