#!/bin/bash

# Quick SSH Key Fix Script
# Immediately fixes SSH key line endings without needing Vault
# Usage: ./scripts/fix-ssh-keys.sh

SSH_DIR="$HOME/ssh"

if [ ! -d "$SSH_DIR" ]; then
    echo "Error: SSH directory not found at $SSH_DIR"
    exit 1
fi

echo "Fixing SSH key line endings in $SSH_DIR..."

fixed_count=0
for key_file in "$SSH_DIR"/*; do
    if [ -f "$key_file" ]; then
        key_name=$(basename "$key_file")
        
        # Check if file has CRLF
        if file "$key_file" | grep -q CRLF; then
            echo "  Fixing: $key_name"
            sed -i 's/\r$//' "$key_file"
            chmod 600 "$key_file"
            fixed_count=$((fixed_count + 1))
        fi
    fi
done

echo ""
if [ $fixed_count -eq 0 ]; then
    echo "No SSH keys needed fixing - all look good!"
else
    echo "Fixed $fixed_count SSH key(s)"
    echo ""
    echo "Verification:"
    for key_file in "$SSH_DIR"/*_id_ed25519 "$SSH_DIR"/*_id_rsa; do
        if [ -f "$key_file" ]; then
            key_name=$(basename "$key_file")
            if ssh-keygen -l -f "$key_file" &> /dev/null; then
                echo "  ✓ $key_name - Valid"
            else
                echo "  ✗ $key_name - Still invalid"
            fi
        fi
    done
fi
