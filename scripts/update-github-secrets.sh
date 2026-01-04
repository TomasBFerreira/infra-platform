#!/bin/bash

# Script to update GitHub environment secrets
# Usage: ./scripts/update-github-secrets.sh <github_token> <environment>

set -e

GITHUB_TOKEN="$1"
ENVIRONMENT="$2"
REPO_OWNER="${3:-TomasBFerreira}"
REPO_NAME="${4:-infra-platform}"

if [ -z "$GITHUB_TOKEN" ] || [ -z "$ENVIRONMENT" ]; then
    echo "Usage: $0 <github_token> <environment> [repo_owner] [repo_name]"
    echo "Example: $0 ghp_xxxxxxxxxxxx dev"
    exit 1
fi

echo "Updating secrets for $REPO_OWNER/$REPO_NAME environment: $ENVIRONMENT"

# Function to update a secret
update_secret() {
    local secret_name="$1"
    local secret_value="$2"
    
    echo "Updating secret: $secret_name"
    
    # Get the repository ID
    REPO_ID=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME" | \
        jq -r '.id')
    
    # Get the environment ID
    ENV_ID=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/environments/$ENVIRONMENT" | \
        jq -r '.id')
    
    # Create or update the secret
    curl -s -X PUT \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/environments/$ENVIRONMENT/secrets/$secret_name" \
        -d "{
            \"name\": \"$secret_name\",
            \"value\": \"$secret_value\"
        }" | jq -r '.message // "Updated"'
}

# Read current values from .env file (if it exists)
if [ -f ".env" ]; then
    echo "Reading values from .env file..."
    source .env
else
    echo "No .env file found. Using default values..."
fi

# Update secrets with current values
update_secret "VAULT_ADDR" "${VAULT_ADDR:-http://localhost:8200}"
update_secret "VAULT_TOKEN" "${VAULT_TOKEN:-myroot}"
update_secret "PVE_API" "${PVE_API:-http://192.168.50.202:8006/api2/json}"
update_secret "PVE_USER" "${PVE_USER:-root@pam}"
update_secret "PVE_PASS" "${PVE_PASS:-your_password_here}"
update_secret "SSH_USER" "${SSH_USER:-root}"

echo "✅ Secrets updated successfully!"
echo ""
echo "Note: You may need to update PVE_PASS manually if it contains special characters"
echo "Check GitHub > Settings > Environments > $ENVIRONMENT > Environment secrets"
