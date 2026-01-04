# Updating GitHub Environment Secrets

This guide shows how to update GitHub environment secrets for your infrastructure platform.

## Quick Fix for Current Issue

Your Vault secrets are outdated. Update these in GitHub:

1. Go to: **GitHub > Settings > Environments > dev > Environment secrets**
2. Update these secrets:

```bash
VAULT_ADDR=http://localhost:8200
VAULT_TOKEN=myroot
```

## Current Required Secrets

For the dev environment, you need these secrets:

| Secret Name | Example Value | Description |
|-------------|---------------|-------------|
| `VAULT_ADDR` | `http://localhost:8200` | Vault server URL |
| `VAULT_TOKEN` | `myroot` | Vault root token |
| `PVE_API` | `http://192.168.50.202:8006/api2/json` | Proxmox API URL |
| `PVE_USER` | `root@pam` | Proxmox username |
| `PVE_PASS` | `your_password_here` | Proxmox password |
| `SSH_USER` | `root` | SSH user for VMs |

## Programmatic Updates

### Using the Update Script

1. **Get a GitHub Personal Access Token**:
   - Go to GitHub > Settings > Developer settings > Personal access tokens
   - Create token with `repo` and `environment` scopes

2. **Run the update script**:
   ```bash
   # Using values from .env file
   ./scripts/update-github-secrets.sh ghp_your_github_token dev
   
   # Or specify custom values
   PVE_PASS="new_password" ./scripts/update-github-secrets.sh ghp_your_github_token dev
   ```

### Manual Updates

1. Go to **GitHub > Settings > Environments > dev > Environment secrets**
2. Click **Add secret** or update existing ones
3. Enter the name and value
4. Click **Save secret**

## Adding New Nodes

When adding new nodes, update these secrets:

1. **Add to .env file**:
   ```bash
   NEW_NODE_NAME="new-node"
   NEW_NODE_IP="192.168.50.XXX"
   ```

2. **Update GitHub secrets**:
   ```bash
   # Add node-specific secrets
   update_secret "NEW_NODE_API" "http://$NEW_NODE_IP:8006/api2/json"
   update_secret "NEW_NODE_USER" "root@pam"
   update_secret "NEW_NODE_PASS" "password"
   ```

3. **Update Terraform variables** in the new node's configuration

## Security Notes

- **Never commit secrets to Git**
- **Use strong passwords** for production
- **Rotate tokens regularly**
- **Limit token scopes** to minimum required
- **Use environment-specific secrets** (dev vs prod)

## Troubleshooting

### Vault Token Issues
- Ensure Vault is running: `vault status`
- Check token: `vault token lookup myroot`
- Verify address: `curl http://localhost:8200/v1/sys/health`

### Proxmox Connection Issues
- Check Proxmox API accessibility
- Verify user permissions
- Test API: `curl -k https://your-proxmox:8006/api2/json/version`

### GitHub API Issues
- Check token permissions
- Verify token hasn't expired
- Ensure environment exists
