#Requires -Version 5.1
<#
.SYNOPSIS
    One-time setup for Vault SSH Key Sync.

.DESCRIPTION
    - Prompts for the Vault address and token
    - Encrypts the token with Windows DPAPI (only you can decrypt it)
    - Saves config to %APPDATA%\VaultSshSync\config.json
    - Runs an initial sync
    - Registers a Windows Task Scheduler task to sync at every logon
    - Optionally registers a repeat trigger every 30 minutes
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$AppName    = "VaultSshSync"
$TaskName   = "VaultSshSync"
$ConfigDir  = "$env:APPDATA\$AppName"
$ConfigFile = "$ConfigDir\config.json"
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$SyncScript = Join-Path $ScriptDir "Sync-VaultSshKeys.ps1"

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  Vault SSH Key Sync — Setup" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# Check that the sync script exists
# ---------------------------------------------------------------------------
if (-not (Test-Path $SyncScript)) {
    Write-Host "ERROR: Sync-VaultSshKeys.ps1 not found at $SyncScript" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# Collect config from user
# ---------------------------------------------------------------------------
$defaultAddr = "http://192.168.50.200:8200"
$existingConfig = $null
if (Test-Path $ConfigFile) {
    $existingConfig = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    $defaultAddr = $existingConfig.vault_address
}

Write-Host "Bootstrap Vault address (KV v2, all SSH keys live here):"
$vaultAddr = Read-Host "  Address [$defaultAddr]"
if ([string]::IsNullOrWhiteSpace($vaultAddr)) { $vaultAddr = $defaultAddr }
$vaultAddr = $vaultAddr.TrimEnd('/')

Write-Host ""
Write-Host "Vault token  (use your bootstrap root token, or a read-only token" -ForegroundColor Yellow
Write-Host "             scoped to 'secret/data/ssh_keys/*')" -ForegroundColor Yellow
Write-Host "The token is encrypted with Windows DPAPI — only your account can read it."
$tokenSecure = Read-Host "  Token" -AsSecureString
$token = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($tokenSecure))

if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Host "ERROR: Token cannot be empty." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# Validate connectivity before saving
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Validating connection to Vault ..." -NoNewline
try {
    $health = Invoke-RestMethod `
        -Uri    "$vaultAddr/v1/sys/health" `
        -Method GET `
        -TimeoutSec 10 `
        -ErrorAction Stop
    if ($health.sealed) {
        Write-Host " WARNING: Vault is sealed." -ForegroundColor Yellow
    } else {
        Write-Host " OK (initialized, unsealed)" -ForegroundColor Green
    }
} catch {
    Write-Host " FAILED: $_" -ForegroundColor Red
    Write-Host "Check that $vaultAddr is reachable from this machine." -ForegroundColor Yellow
    $continue = Read-Host "Continue anyway? [y/N]"
    if ($continue -notmatch '^[Yy]') { exit 1 }
}

# ---------------------------------------------------------------------------
# Encrypt token with DPAPI and save config
# ---------------------------------------------------------------------------
Add-Type -AssemblyName System.Security
$tokenBytes = [System.Text.Encoding]::UTF8.GetBytes($token)
$encrypted  = [System.Security.Cryptography.ProtectedData]::Protect(
    $tokenBytes, $null,
    [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
$encryptedB64 = [Convert]::ToBase64String($encrypted)

New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null

$configObj = [ordered]@{
    vault_address      = $vaultAddr
    vault_token_dpapi  = $encryptedB64   # DPAPI-encrypted, this user only
}
$configObj | ConvertTo-Json | Set-Content $ConfigFile -Encoding UTF8

Write-Host "Config saved to $ConfigFile" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Register Task Scheduler task (runs at logon, highest privileges)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Registering startup task '$TaskName' in Task Scheduler ..."

# Build the PowerShell command that runs hidden
$psArgs = "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$SyncScript`""

$action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $psArgs
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

# Optional: also repeat every 30 minutes throughout the day
$repeatInterval = (New-TimeSpan -Minutes 30)
$trigger.RepetitionDuration = (New-TimeSpan -Hours 24)
$trigger.RepetitionInterval = $repeatInterval

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -StartWhenAvailable `
    -DontStopIfGoingOnBatteries `
    -AllowStartIfOnBatteries

$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Highest

# Remove any existing task first
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask `
    -TaskName  $TaskName `
    -Action    $action `
    -Trigger   $trigger `
    -Settings  $settings `
    -Principal $principal `
    -Force | Out-Null

Write-Host "Task registered — will run at logon and every 30 min." -ForegroundColor Green

# ---------------------------------------------------------------------------
# Run initial sync now
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Running initial sync ..."
& powershell.exe -NonInteractive -ExecutionPolicy Bypass -File $SyncScript

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  Setup complete!" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "SSH keys have been written to: $env:USERPROFILE\.ssh\" -ForegroundColor White
Write-Host "Logs at: $ConfigDir\sync.log" -ForegroundColor White
Write-Host ""
Write-Host "To re-run manually:" -ForegroundColor Gray
Write-Host "  powershell -ExecutionPolicy Bypass -File `"$SyncScript`"" -ForegroundColor Gray
Write-Host ""
Write-Host "To uninstall: run Uninstall.ps1" -ForegroundColor Gray
Write-Host ""
