# Dev Branch Infrastructure Management

This guide explains how to use the dev branch workflow to manage your Proxmox infrastructure through GitHub Actions.

## Overview

The dev branch provides a safe environment to test infrastructure changes before deploying to production. Changes to Terraform and Ansible files automatically trigger workflows that:

1. **Detect Changes**: Identifies which infrastructure components have changed
2. **Plan Changes**: Shows what will be modified (for pull requests)
3. **Apply Changes**: Implements the infrastructure changes (when pushed to dev)
4. **Run Configuration**: Applies Ansible playbooks to configure systems

## Workflow Triggers

### Automatic Triggers

- **Push to dev branch**: Automatically applies infrastructure changes
- **Pull Request to dev**: Generates plan previews and syntax checks

### Manual Triggers

- **Workflow Dispatch**: Manually trigger with specific actions:
  - Terraform action: `plan`, `apply`, or `destroy`
  - Ansible action: `run`, `check`, or `skip`

## Workflow Files

### 1. `dev-infrastructure.yml`

Main workflow that manages infrastructure changes:

**Features:**
- **Change Detection**: Only runs jobs for components that actually changed
- **Parallel Execution**: Media Stack and Network VM can run independently
- **Conditional Logic**: Different behavior for different trigger types
- **Summary Report**: Provides detailed results in GitHub Actions summary

**Jobs:**
- `detect-changes`: Analyzes git diff to determine what changed
- `terraform-media-stack`: Manages media stack infrastructure
- `terraform-network-vm`: Manages network VM infrastructure  
- `ansible-media-stack`: Configures media stack systems
- `ansible-network-vm`: Configures network VM systems
- `summary`: Provides overall workflow results

### 2. `plan-preview.yml`

Generates preview information for pull requests:

**Features:**
- **Terraform Plans**: Shows what infrastructure changes will occur
- **Ansible Syntax Checks**: Validates playbook syntax
- **Inventory Validation**: Checks Ansible inventory files

## Directory Structure

```
├── terraform/dev/
│   ├── media-stack/          # Media stack infrastructure
│   └── network-vm/           # Network VM infrastructure
├── ansible/dev/
│   ├── media-stack/         # Media stack configuration
│   └── network-vm/          # Network VM configuration
└── .github/workflows/
    ├── dev-infrastructure.yml # Main dev workflow
    └── plan-preview.yml      # PR preview workflow
```

## Usage Examples

### 1. Make Infrastructure Changes

```bash
# Make changes to Terraform or Ansible files
vim terraform/dev/media-stack/main.tf
vim ansible/dev/media-stack/roles/common/tasks/main.yml

# Commit and push to dev branch
git add .
git commit -m "feat: Update media stack configuration"
git push origin dev
```

**Result**: GitHub Actions automatically detects changes and applies them.

### 2. Create Pull Request

```bash
# Create feature branch
git checkout -b feature/new-media-service

# Make changes
vim terraform/dev/media-stack/main.tf
vim ansible/dev/media-stack/roles/new-service/tasks/main.yml

# Create PR targeting dev branch
git push origin feature/new-media-service
# Then create PR in GitHub UI
```

**Result**: Plan preview workflow runs showing what will change.

### 3. Manual Workflow Trigger

1. Go to **Actions** tab in GitHub
2. Select **Dev Infrastructure Management** workflow
3. Click **Run workflow**
4. Choose options:
   - Terraform action: `plan`, `apply`, or `destroy`
   - Ansible action: `run`, `check`, or `skip`

## Change Detection Logic

The workflow uses git diff to detect changes:

- **Terraform changes**: Files in `terraform/dev/`
- **Ansible changes**: Files in `ansible/dev/`
- **Media Stack changes**: Files in `terraform/dev/media-stack/` or `ansible/dev/media-stack/`
- **Network VM changes**: Files in `terraform/dev/network-vm/` or `ansible/dev/network-vm/`

## Environment Variables

- `TF_VERSION`: Terraform version (1.6.4)
- `VAULT_ADDR`: Vault URL (http://localhost:8200)
- `VAULT_TOKEN`: Vault token (myroot for dev)

## Required Secrets

Configure these in GitHub repository settings:

- `PVE_API`: Proxmox API URL
- `PVE_USER`: Proxmox username
- `PVE_PASS`: Proxmox password
- `SSH_USER`: SSH user for Ansible connections

## Safety Features

### 1. Change Detection
- Only runs jobs for components that actually changed
- Prevents unnecessary infrastructure modifications

### 2. Plan Preview
- Pull requests show what will change before merging
- Syntax validation prevents broken configurations

### 3. Conditional Execution
- Terraform apply only runs on dev branch pushes
- Manual control over destroy operations

### 4. Summary Reports
- Clear visibility into what was executed
- Links to detailed job outputs

## Best Practices

### 1. Development Workflow
```bash
# 1. Create feature branch
git checkout -b feature/new-infrastructure

# 2. Make changes
vim terraform/dev/media-stack/main.tf
vim ansible/dev/media-stack/playbook.yml

# 3. Test locally
./scripts/run-terraform.sh plan
./scripts/run-ansible.sh playbook --syntax-check playbook.yml

# 4. Create PR
git push origin feature/new-infrastructure
# Create PR targeting dev branch

# 5. Review plan preview
# Check GitHub Actions for plan preview results

# 6. Merge to dev
# PR approved and merged to dev branch

# 7. Verify deployment
# Check dev-infrastructure workflow results
```

### 2. Infrastructure Changes
- **Small Changes**: Make incremental changes rather than large overhauls
- **Test Locally**: Use wrapper scripts to test before pushing
- **Review Plans**: Always review Terraform plans in PRs
- **Monitor Results**: Check workflow summaries after each run

### 3. Ansible Playbooks
- **Idempotent**: Ensure playbooks can run multiple times safely
- **Syntax Check**: Validate syntax before committing
- **Testing**: Use `--check` mode for dry runs

## Troubleshooting

### Common Issues

1. **Change Detection Not Working**
   - Check file paths match expected patterns
   - Verify git diff is working correctly

2. **Terraform Failures**
   - Check Proxmox API credentials
   - Verify Vault token is valid
   - Review Terraform plan output

3. **Ansible Failures**
   - Check SSH key access from Vault
   - Verify inventory file syntax
   - Test connectivity manually

### Debugging

1. **Check Workflow Logs**
   - Go to Actions tab
   - Click on specific workflow run
   - Review job outputs and error messages

2. **Manual Testing**
   ```bash
   # Test Terraform locally
   ./scripts/run-terraform.sh plan
   
   # Test Ansible locally
   ./scripts/run-ansible.sh playbook --syntax-check playbook.yml
   ```

3. **Vault Issues**
   ```bash
   # Check Vault connectivity
   curl http://localhost:8200/v1/sys/health
   
   # Check Vault secrets
   vault kv list secret/
   ```

## Next Steps

1. **Set up Secrets**: Configure required repository secrets
2. **Test Workflow**: Make a small change and verify it works
3. **Review Results**: Check summary reports and job outputs
4. **Refine Process**: Adjust based on your specific needs

This dev workflow provides a safe, automated way to manage your Proxmox infrastructure while maintaining visibility and control over changes.
