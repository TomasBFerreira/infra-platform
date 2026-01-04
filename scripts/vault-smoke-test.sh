#!/bin/bash

set -e

# Vault Smoke Test
# Tests Vault connectivity and secret retrieval

echo "========================================="
echo "Vault Smoke Test"
echo "========================================="

# Configuration
VAULT_ADDR="http://localhost:8200"
VAULT_TOKEN="myroot"

# Test 1: Vault Health Check
echo "🔍 Test 1: Vault Health Check"
HEALTH_RESPONSE=$(curl -s "$VAULT_ADDR/v1/sys/health")
if echo "$HEALTH_RESPONSE" | grep -q '"initialized":true'; then
    echo "✅ Vault is initialized"
else
    echo "❌ Vault is not initialized"
    exit 1
fi

if echo "$HEALTH_RESPONSE" | grep -q '"sealed":false'; then
    echo "✅ Vault is unsealed"
else
    echo "❌ Vault is sealed"
    exit 1
fi

# Test 2: Authentication
echo ""
echo "🔍 Test 2: Vault Authentication"
AUTH_RESPONSE=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/auth/token/lookup-self")
if echo "$AUTH_RESPONSE" | grep -q '"id":"myroot"'; then
    echo "✅ Vault authentication successful"
else
    echo "❌ Vault authentication failed"
    echo "Response: $AUTH_RESPONSE"
    exit 1
fi

# Test 3: SSH Keys Exist
echo ""
echo "🔍 Test 3: SSH Keys in Vault"
SSH_RESPONSE=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/secret/data/ssh_keys/media-stack_worker")
if echo "$SSH_RESPONSE" | grep -q '"data":{'; then
    echo "✅ Media-stack SSH keys exist in Vault"
    
    # Extract and display key info
    PUBLIC_KEY=$(echo "$SSH_RESPONSE" | jq -r '.data.data.public' 2>/dev/null | head -c 50)...
    echo "   Public key preview: $PUBLIC_KEY"
else
    echo "❌ Media-stack SSH keys not found in Vault"
    echo "   Run: ./scripts/setup-vault-secrets.sh"
    exit 1
fi

# Test 4: Proxmox Credentials
echo ""
echo "🔍 Test 4: Proxmox Credentials in Vault"
PROXMOX_RESPONSE=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/secret/data/proxmox")
if echo "$PROXMOX_RESPONSE" | grep -q '"data":{'; then
    echo "✅ Proxmox credentials exist in Vault"
    
    # Extract and display credential info
    API_URL=$(echo "$PROXMOX_RESPONSE" | jq -r '.data.data.api_url' 2>/dev/null)
    USER=$(echo "$PROXMOX_RESPONSE" | jq -r '.data.data.user' 2>/dev/null)
    echo "   API URL: $API_URL"
    echo "   User: $USER"
else
    echo "❌ Proxmox credentials not found in Vault"
    echo "   Run: ./scripts/setup-vault-secrets.sh"
    exit 1
fi

# Test 5: Terraform Container Access
echo ""
echo "🔍 Test 5: Terraform Container Vault Access"
cd /app/infra-platform

# Test if container can reach host Vault using wget
if docker exec terraform-runner sh -c "wget -q -O - http://host.docker.internal:8200/v1/sys/health" > /dev/null 2>&1; then
    echo "✅ Terraform container can reach Vault"
else
    echo "❌ Terraform container cannot reach Vault"
    echo "   Check Docker networking"
    exit 1
fi

# Test Terraform init with proper environment
if docker exec terraform-runner sh -c "cd /workspace/terraform/dev/media-stack && TF_VAR_vault_token='myroot' TF_VAR_vault_address='http://host.docker.internal:8200' terraform init" > /dev/null 2>&1; then
    echo "✅ Terraform container can access Vault"
else
    echo "❌ Terraform container cannot access Vault"
    echo "   Check Vault connectivity from container"
    exit 1
fi

# Test 6: Ansible Container Access
echo ""
echo "🔍 Test 6: Ansible Container Vault Access"
if docker exec ansible-runner sh -c "wget -q -O - http://host.docker.internal:8200/v1/sys/health" > /dev/null 2>&1; then
    echo "✅ Ansible container can access Vault"
else
    echo "❌ Ansible container cannot access Vault"
    echo "   Check Vault connectivity from container"
    exit 1
fi

# Test 7: End-to-End Test (Dry Run)
echo ""
echo "🔍 Test 7: End-to-End Test (Terraform Plan)"
cd /app/infra-platform

# Set environment variables for Terraform
export TF_VAR_proxmox_api_url="http://192.168.50.202:8006/api2/json"
export TF_VAR_proxmox_user="root@pam"
export TF_VAR_proxmox_password="Tomtom22!"
export TF_VAR_vault_token="myroot"
export TF_VAR_vault_address="http://host.docker.internal:8200"

if ./scripts/run-terraform.sh -chdir=terraform/dev/media-stack plan -out=test.tfplan > /dev/null 2>&1; then
    echo "✅ End-to-end Terraform test successful"
    rm -f test.tfplan  # Clean up
else
    echo "❌ End-to-end Terraform test failed"
    echo "   Check Proxmox connectivity and Vault secrets"
    echo "   Note: Proxmox connection errors are expected if Proxmox is not accessible"
    exit 1
fi

echo ""
echo "========================================="
echo "🎉 All smoke tests passed!"
echo "========================================="
echo ""
echo "Your Vault setup is ready for GitHub Actions!"
echo ""
echo "Next steps:"
echo "1. Push changes to dev branch"
echo "2. Monitor GitHub Actions execution"
echo "3. Check infrastructure deployment"
echo ""
