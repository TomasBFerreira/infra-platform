#!/bin/bash

# Entrypoint script for Ansible container
# Fixes SSH key formatting issues before running commands

set -e

# Function to fix SSH key line endings and decode base64 if needed
fix_ssh_key() {
    local key_file="$1"
    local key_name=$(basename "$key_file")
    
    if [ -f "$key_file" ]; then
        # Check if the file has carriage returns (Windows line endings)
        if file "$key_file" | grep -q CRLF; then
            echo "Fixing CRLF line endings in: $key_name"
            sed -i 's/\r$//' "$key_file"
        fi
        
        # Check if key appears to be base64-encoded (starts with base64 chars, not PEM header)
        local first_line=$(head -1 "$key_file")
        if [[ ! "$first_line" =~ ^-----BEGIN ]]; then
            # Likely base64-encoded, try to decode it
            if head -c 100 "$key_file" | grep -q '^[A-Za-z0-9+/=]*$'; then
                echo "Detected base64-encoded SSH key: $key_name - decoding..."
                local decoded_content
                decoded_content=$(base64 -d "$key_file" 2>/dev/null) || {
                    echo "ERROR: Failed to decode base64 key: $key_name"
                    return 1
                }
                echo "$decoded_content" > "$key_file"
                chmod 600 "$key_file"
            fi
        fi
        
        # Check file size - keys should not be empty or tiny
        local file_size=$(wc -c < "$key_file")
        if [ "$file_size" -lt 1700 ]; then
            echo "ERROR: SSH key appears to be invalid or corrupted: $key_name (size: $file_size bytes)"
            return 1
        fi
        
        # Verify the key format
        if ! ssh-keygen -l -f "$key_file" &> /dev/null; then
            echo "ERROR: SSH key format is invalid: $key_name"
            echo "  This key may be corrupted or in an unsupported format"
            echo "  Key should start with: -----BEGIN OPENSSH PRIVATE KEY-----"
            echo "  First line of file:"
            head -1 "$key_file" | head -c 50
            echo ""
            return 1
        fi
        
        echo "✓ SSH key OK: $key_name"
    fi
}

# Fix all SSH keys in /root/ssh directory
if [ -d "/root/ssh" ]; then
    echo "=========================================="
    echo "Checking SSH keys in /root/ssh..."
    echo "=========================================="
    
    key_errors=0
    
    # Check ED25519 keys
    for key_file in /root/ssh/*_id_ed25519; do
        if [ -f "$key_file" ]; then
            if ! fix_ssh_key "$key_file"; then
                key_errors=$((key_errors + 1))
            fi
        fi
    done
    
    # Check RSA keys
    for key_file in /root/ssh/*_id_rsa; do
        if [ -f "$key_file" ]; then
            if ! fix_ssh_key "$key_file"; then
                key_errors=$((key_errors + 1))
            fi
        fi
    done
    
    echo "=========================================="
    
    if [ $key_errors -gt 0 ]; then
        echo "⚠  WARNING: $key_errors SSH key(s) have issues!"
        echo "  This may cause Ansible connection failures."
        echo "  Consider retrieving fresh keys from Vault:"
        echo "  ./scripts/setup-ssh-keys.sh"
        echo "=========================================="
    fi
fi

# Execute the passed command
exec "$@"
