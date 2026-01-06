#!/bin/bash

# Debug script to inspect SSH keys for root cause analysis
# Usage: ./scripts/debug-ssh-keys.sh

SSH_DIR="$HOME/ssh"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║          SSH Key Debug Analysis - Root Cause Detection         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [ ! -d "$SSH_DIR" ]; then
    echo "ERROR: SSH directory not found at $SSH_DIR"
    exit 1
fi

for key_file in "$SSH_DIR"/*_id_ed25519 "$SSH_DIR"/*_id_rsa; do
    if [ -f "$key_file" ]; then
        key_name=$(basename "$key_file")
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "File: $key_name"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # File info
        echo "Location: $key_file"
        echo "Permissions: $(stat -c %a "$key_file" 2>/dev/null || stat -f %A "$key_file")"
        echo "Size: $(wc -c < "$key_file") bytes"
        
        # Check for line endings
        echo ""
        echo "Line Ending Analysis:"
        if file "$key_file" | grep -q CRLF; then
            echo "  ⚠ File has CRLF line endings (Windows style)"
        else
            echo "  ✓ File has LF line endings (Unix style)"
        fi
        
        # Check for NULL bytes
        if file "$key_file" | grep -q "data"; then
            echo "  ⚠ File appears to be binary data (corrupted)"
        else
            echo "  ✓ File appears to be text"
        fi
        
        # Check header and footer
        echo ""
        echo "Key Format Analysis:"
        first_line=$(head -1 "$key_file")
        last_line=$(tail -1 "$key_file")
        
        if [ "$first_line" = "-----BEGIN OPENSSH PRIVATE KEY-----" ]; then
            echo "  ✓ Correct header: BEGIN OPENSSH PRIVATE KEY"
        else
            echo "  ✗ Invalid header!"
            echo "    Expected: -----BEGIN OPENSSH PRIVATE KEY-----"
            echo "    Got:      $first_line"
        fi
        
        if [ "$last_line" = "-----END OPENSSH PRIVATE KEY-----" ]; then
            echo "  ✓ Correct footer: END OPENSSH PRIVATE KEY"
        else
            echo "  ✗ Invalid footer!"
            echo "    Expected: -----END OPENSSH PRIVATE KEY-----"
            echo "    Got:      $last_line"
        fi
        
        # SSH-keygen validation
        echo ""
        echo "SSH-Keygen Validation:"
        if ssh-keygen -l -f "$key_file" &> /dev/null; then
            echo "  ✓ Key is valid"
            ssh-keygen -l -f "$key_file"
        else
            echo "  ✗ Key validation failed"
            ssh-keygen -l -f "$key_file" 2>&1 || true
        fi
        
        # Hex dump of first 100 bytes
        echo ""
        echo "First 100 bytes (hex):"
        hexdump -C "$key_file" | head -7
        
        # Recommendations
        echo ""
        echo "Recommendations:"
        if [ "$first_line" != "-----BEGIN OPENSSH PRIVATE KEY-----" ]; then
            echo "  1. Key header is invalid - likely corrupted during transfer/storage"
            echo "  2. Try retrieving a fresh copy from Vault:"
            echo "     ./scripts/setup-ssh-keys.sh"
        elif [ "$(wc -c < "$key_file")" -lt 1700 ]; then
            echo "  1. Key file is too small - likely truncated"
            echo "  2. Try retrieving a fresh copy from Vault:"
            echo "     ./scripts/setup-ssh-keys.sh"
        else
            echo "  1. Key appears structurally valid"
            echo "  2. Issue may be with Vault storage or retrieval"
            echo "  3. Try: ./scripts/fix-ssh-keys.sh"
        fi
        
        echo ""
    fi
done

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                   Diagnosis Complete                           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
