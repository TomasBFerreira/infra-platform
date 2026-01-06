#!/bin/bash

# SSH Key Diagnostic and Repair Script
# Diagnoses and fixes SSH key issues for Ansible automation
# Usage: ./scripts/diagnose-ssh-keys.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

SSH_DIR="$HOME/ssh"
KNOWN_KEYS=("infra-lxc_worker_id_ed25519" "network-vm_worker_id_ed25519" "media-stack_worker_id_ed25519")

echo "=========================================="
echo "SSH Key Diagnostic Report"
echo "=========================================="
echo ""

# Check SSH directory exists
if [ ! -d "$SSH_DIR" ]; then
    echo "⚠ SSH directory does not exist: $SSH_DIR"
    echo "Creating it now..."
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
else
    echo "✓ SSH directory exists: $SSH_DIR"
fi

echo ""
echo "Checking for SSH keys..."
echo "----------------------------------------"

key_count=0
invalid_count=0

for key_file in "$SSH_DIR"/*; do
    if [ -f "$key_file" ]; then
        key_name=$(basename "$key_file")
        key_count=$((key_count + 1))
        
        echo ""
        echo "Key: $key_name"
        
        # Check file size
        file_size=$(wc -c < "$key_file")
        echo "  Size: $file_size bytes"
        
        # Check line endings
        if file "$key_file" | grep -q CRLF; then
            echo "  Line endings: ✗ CRLF (Windows) - WILL CAUSE ERRORS"
            invalid_count=$((invalid_count + 1))
        else
            echo "  Line endings: ✓ LF (Unix)"
        fi
        
        # Check permissions
        perms=$(stat -c %a "$key_file" 2>/dev/null || stat -f %A "$key_file" 2>/dev/null)
        if [ "$perms" = "600" ]; then
            echo "  Permissions: ✓ 600"
        else
            echo "  Permissions: ✗ $perms (should be 600)"
            invalid_count=$((invalid_count + 1))
        fi
        
        # Check key format
        if ssh-keygen -l -f "$key_file" &> /dev/null; then
            echo "  Format: ✓ Valid SSH key"
        else
            echo "  Format: ✗ Invalid or corrupted"
            invalid_count=$((invalid_count + 1))
        fi
        
        # Show first line of key
        first_line=$(head -1 "$key_file")
        echo "  Key type: ${first_line:0:30}..."
    fi
done

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Total keys found: $key_count"
echo "Issues detected: $invalid_count"
echo ""

if [ $invalid_count -gt 0 ]; then
    echo "⚠ Issues detected! Would you like to repair them? (y/n)"
    read -r -n 1 response
    echo ""
    
    if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
        echo ""
        echo "Repairing SSH keys..."
        echo "----------------------------------------"
        
        for key_file in "$SSH_DIR"/*; do
            if [ -f "$key_file" ]; then
                key_name=$(basename "$key_file")
                echo "Fixing: $key_name"
                
                # Fix line endings
                sed -i 's/\r$//' "$key_file"
                
                # Fix permissions
                chmod 600 "$key_file"
                
                # Verify
                if ssh-keygen -l -f "$key_file" &> /dev/null; then
                    echo "  ✓ Fixed successfully"
                else
                    echo "  ✗ Still has issues - may need to re-import from Vault"
                fi
            fi
        done
        
        echo ""
        echo "✓ Repair complete!"
    fi
else
    echo "✓ All SSH keys are properly configured!"
fi

echo ""
echo "Next steps:"
echo "1. Test SSH connection: ssh -i ~/ssh/infra-lxc_worker_id_ed25519 root@192.168.50.221"
echo "2. Run Ansible: ./scripts/run-ansible.sh playbook ..."
echo ""
