#Requires -Version 5.1
<#
.SYNOPSIS
    Removes Vault SSH Key Sync  -  scheduled task and config.
#>

$AppName  = "VaultSshSync"
$TaskName = "VaultSshSync"
$ConfigDir = "$env:APPDATA\$AppName"

Write-Host "Removing scheduled task '$TaskName' ..." -NoNewline
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Write-Host " done" -ForegroundColor Green

$remove = Read-Host "Remove config and logs at $ConfigDir ? [y/N]"
if ($remove -match '^[Yy]') {
    Remove-Item -Path $ConfigDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Config removed." -ForegroundColor Green
} else {
    Write-Host "Config kept at $ConfigDir" -ForegroundColor Yellow
}

Write-Host "Uninstall complete." -ForegroundColor Cyan
