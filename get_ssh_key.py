#!/usr/bin/env python3
import json
import subprocess

# Get the secret from Vault
result = subprocess.run(
    ['vault', 'kv', 'get', '-format=json', 'secret/ssh_keys/media-stack_worker'],
    capture_output=True,
    text=True
)

# Parse the JSON and extract the private key
secret = json.loads(result.stdout)
private_key = secret['data']['data']['private']

# Save the private key to a file
with open('/root/.ssh/media-stack_worker_id_ed25519', 'w') as f:
    f.write(private_key)

# Set the correct permissions
subprocess.run(['chmod', '600', '/root/.ssh/media-stack_worker_id_ed25519'])

print("SSH key saved successfully")
