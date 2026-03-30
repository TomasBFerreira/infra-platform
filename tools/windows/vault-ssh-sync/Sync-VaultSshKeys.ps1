#Requires -Version 5.1
<#
.SYNOPSIS
    Syncs SSH keys from HashiCorp Vault to %USERPROFILE%\.ssh\

.DESCRIPTION
    Reads all secrets under secret/ssh_keys/* from the configured Vault instance
    (KV v2) and writes them as SSH key files with correct Windows permissions.
    Designed to run silently at Windows logon via Task Scheduler.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$AppName    = "VaultSshSync"
$ConfigDir  = "$env:APPDATA\$AppName"
$ConfigFile = "$ConfigDir\config.json"
$LogFile    = "$ConfigDir\sync.log"
$MaxLogBytes = 1MB

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"

    # Rotate log when it gets too large
    if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt $MaxLogBytes) {
        Move-Item $LogFile "$LogFile.old" -Force
    }
    Add-Content -Path $LogFile -Value $line
}

# ---------------------------------------------------------------------------
# Windows Toast notification (Windows 10/11 — fails silently on older OS)
# ---------------------------------------------------------------------------
function Show-Toast {
    param([string]$Title, [string]$Message, [string]$AppId = $AppName)
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager,
                 Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument,
                 Windows.Data.Xml.Dom, ContentType = WindowsRuntime]

        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml(@"
<toast duration="short">
  <visual><binding template="ToastGeneric">
    <text>$([System.Security.SecurityElement]::Escape($Title))</text>
    <text>$([System.Security.SecurityElement]::Escape($Message))</text>
  </binding></visual>
</toast>
"@)
        $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId).Show($toast)
    } catch {
        # Toast not available — silently skip
    }
}

# ---------------------------------------------------------------------------
# DPAPI helpers — encrypt/decrypt token bound to current Windows user account
# ---------------------------------------------------------------------------
function Protect-Token([string]$PlainText) {
    Add-Type -AssemblyName System.Security
    $bytes     = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $encrypted = [System.Security.Cryptography.ProtectedData]::Protect(
        $bytes, $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    return [Convert]::ToBase64String($encrypted)
}

function Unprotect-Token([string]$Base64Cipher) {
    Add-Type -AssemblyName System.Security
    $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
        [Convert]::FromBase64String($Base64Cipher), $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

# ---------------------------------------------------------------------------
# Set strict SSH private-key file permissions (owner read/write only)
# ---------------------------------------------------------------------------
function Set-SshKeyPermissions([string]$Path) {
    $acl = Get-Acl $Path
    $acl.SetAccessRuleProtection($true, $false)   # break inheritance, clear inherited
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $env:USERNAME, "FullControl",
        [System.Security.AccessControl.AccessControlType]::Allow)
    $acl.SetAccessRule($rule)
    Set-Acl -Path $Path -AclObject $acl
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null

Write-Log "--- Vault SSH key sync started ---"

# Load config
if (-not (Test-Path $ConfigFile)) {
    Write-Log "Config not found at $ConfigFile — run Install.ps1 first." "ERROR"
    Show-Toast "Vault SSH Sync — Error" "Config missing. Run Install.ps1 to set up."
    exit 1
}

$config = Get-Content $ConfigFile -Raw | ConvertFrom-Json

$vaultAddr = $config.vault_address.TrimEnd('/')
if (-not $config.PSObject.Properties['vault_token_dpapi'] -or
    [string]::IsNullOrWhiteSpace($config.vault_token_dpapi)) {
    Write-Log "Vault token not stored in config — run Install.ps1 to reconfigure." "ERROR"
    Show-Toast "Vault SSH Sync — Error" "No vault token found. Run Install.ps1."
    exit 1
}

try {
    $token = Unprotect-Token $config.vault_token_dpapi
} catch {
    Write-Log "Failed to decrypt vault token (DPAPI): $_" "ERROR"
    Show-Toast "Vault SSH Sync — Error" "Could not decrypt vault token. Re-run Install.ps1."
    exit 1
}

$sshDir = "$env:USERPROFILE\.ssh"
New-Item -ItemType Directory -Path $sshDir -Force | Out-Null

# LIST secrets under secret/ssh_keys/
Write-Log "Connecting to $vaultAddr ..."
try {
    $listResp = Invoke-RestMethod `
        -Uri    "$vaultAddr/v1/secret/metadata/ssh_keys?list=true" `
        -Method GET `
        -Headers @{ "X-Vault-Token" = $token } `
        -TimeoutSec 15 `
        -ErrorAction Stop
} catch {
    $msg = "Failed to list Vault secrets: $_"
    Write-Log $msg "ERROR"
    Show-Toast "Vault SSH Sync — Error" "Could not reach vault at $vaultAddr"
    exit 1
}

$keyNames = $listResp.data.keys
if (-not $keyNames -or $keyNames.Count -eq 0) {
    Write-Log "No keys found under secret/ssh_keys/ — nothing to sync." "WARN"
    exit 0
}

Write-Log "Found $($keyNames.Count) key(s): $($keyNames -join ', ')"

$synced = 0
$skipped = 0
$errors  = 0

foreach ($keyName in $keyNames) {
    try {
        $secret = Invoke-RestMethod `
            -Uri    "$vaultAddr/v1/secret/data/ssh_keys/$keyName" `
            -Method GET `
            -Headers @{ "X-Vault-Token" = $token } `
            -TimeoutSec 10 `
            -ErrorAction Stop

        $privateKey = $secret.data.data.private_key
        $publicKey  = $secret.data.data.public_key

        if ($privateKey) {
            $privPath = "$sshDir\$keyName"
            # Normalize to Unix line endings (OpenSSH on Windows still requires these)
            $privateKey = $privateKey.Replace("`r`n", "`n").Replace("`r", "`n")
            # Ensure trailing newline
            if (-not $privateKey.EndsWith("`n")) { $privateKey += "`n" }
            [System.IO.File]::WriteAllText($privPath, $privateKey,
                [System.Text.Encoding]::UTF8)
            Set-SshKeyPermissions $privPath
            Write-Log "  [OK] $keyName"
        }

        if ($publicKey) {
            $pubPath = "$sshDir\$keyName.pub"
            Set-Content -Path $pubPath -Value $publicKey.Trim() -Encoding UTF8
            Write-Log "  [OK] $keyName.pub"
        }

        if ($privateKey -or $publicKey) { $synced++ } else { $skipped++ }

    } catch {
        Write-Log "  [FAIL] $keyName : $_" "ERROR"
        $errors++
    }
}

$summary = "$synced key(s) synced"
if ($skipped -gt 0) { $summary += ", $skipped skipped" }
if ($errors  -gt 0) { $summary += ", $errors failed" }

Write-Log "Done. $summary"

if ($errors -gt 0) {
    Show-Toast "Vault SSH Sync — Warning" "$summary — check $LogFile"
} else {
    Show-Toast "Vault SSH Sync" "$summary to $sshDir"
}
