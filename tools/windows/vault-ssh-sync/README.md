# Vault SSH Key Sync — Windows Tool

Syncs all SSH private/public keys from the bootstrap HashiCorp Vault to `%USERPROFILE%\.ssh\` on your Windows desktop. Runs silently at logon and every 30 minutes via Task Scheduler.

## How it works

- Connects to the **bootstrap Vault** (`http://192.168.50.200:8200`)
- Lists every secret under `secret/ssh_keys/*` (KV v2)
- Writes `<keyname>` (private) and `<keyname>.pub` (public) into `~\.ssh\`
- Sets correct NTFS permissions on private keys (owner read/write only — required by OpenSSH)
- Shows a Windows toast notification on completion or failure
- Your vault token is encrypted with **Windows DPAPI** — only your Windows account can decrypt it

## Setup (one time)

1. Clone/copy this folder to your Windows machine
2. Open PowerShell **as Administrator** and run:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

3. Run the installer:

```powershell
.\Install.ps1
```

You'll be prompted for:
- **Vault address** — defaults to `http://192.168.50.200:8200`
- **Vault token** — use your bootstrap root token (or a read-only token scoped to `secret/data/ssh_keys/*`)

The installer will validate the connection, encrypt the token, save config, register the startup task, and run an initial sync.

## Keys synced

All keys stored in the bootstrap vault under `secret/ssh_keys/`:

| Key name | Used by |
|---|---|
| `github_runner_worker` | GitHub runner LXCs |
| `vault_ct_worker` | Vault CT LXCs |
| `semaphore_worker` | Semaphore LXC |
| `network_vm_worker` | Network VM |
| `rancher_worker` | Rancher LXC |
| `worker_node_worker` | K3s worker nodes |
| `sso_worker` | SSO (Authentik) LXC |
| `torrent_worker` | Torrent LXC |

## Suggested `~/.ssh/config` entries

After the first sync, add these to `%USERPROFILE%\.ssh\config` for convenient direct SSH access:

```ssh-config
# Management / dev machine on betsy
Host tomas-betsy
    HostName 192.168.50.100
    User tomas

# Management / dev machine on benedict
Host tomas-benedict
    HostName 192.168.50.99
    User tomas

# Bootstrap Vault (betsy)
Host bootstrap-vault
    HostName 192.168.50.200
    User root
    IdentityFile ~/.ssh/vault_ct_worker

# GitHub runner (dev — benedict)
Host github-runner-dev
    HostName 192.168.20.101
    User root
    IdentityFile ~/.ssh/github_runner_worker

# Semaphore (dev — benedict)
Host semaphore-dev
    HostName 192.168.20.85
    User root
    IdentityFile ~/.ssh/semaphore_worker
```

## Manual sync

```powershell
powershell -ExecutionPolicy Bypass -File .\Sync-VaultSshKeys.ps1
```

## Logs

`%APPDATA%\VaultSshSync\sync.log`

## Uninstall

```powershell
.\Uninstall.ps1
```
