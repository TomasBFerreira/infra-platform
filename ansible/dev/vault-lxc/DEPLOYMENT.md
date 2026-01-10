# Example workflow for deploying Vault LXC

1. Use Terraform to create the LXC on the prod (betsy) host:
   cd terraform/prod/vault-lxc
   terraform init
   terraform apply

2. Update ansible/dev/vault-lxc/inventory.ini with the new LXC IP if needed.

3. Run the Ansible playbook to provision Vault:
   cd ansible/dev/vault-lxc
   ansible-playbook -i inventory.ini vault-lxc_setup.yml

4. Access Vault UI at http://<LXC_IP>:8200

# Notes
- The LXC will use local-lvm for disk storage.
- Vault will be installed from the official HashiCorp repo.
- Vault data will be stored in /opt/vault/data inside the LXC.
- No TLS is enabled by default (for internal/trusted use only).
