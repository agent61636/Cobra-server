<#
.SYNOPSIS
  Installs the Cobra hiscore agent for the current Windows user (run as `arcade`,
  in a normal, NOT elevated PowerShell window).

  1. Copies agent.ps1 to C:\Cobra\hiscore-agent\ and creates config.json
  2. Asks for the API key and stores it encrypted for this user (DPAPI)
  3. Registers a scheduled task that starts the agent, hidden, at logon
#>
$ErrorActionPreference = 'Stop'
$dest = 'C:\Cobra\hiscore-agent'
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'agent.ps1') $dest -Force
if (-not (Test-Path "$dest\config.json")) {
    Copy-Item (Join-Path $PSScriptRoot 'config.example.json') "$dest\config.json"
    Write-Host "Created $dest\config.json. Check the folder paths match your RetroArch install."
}
& "$dest\agent.ps1" -SetKey -ConfigPath "$dest\config.json"

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dest\agent.ps1`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RestartCount 999 `
    -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName 'Cobra hiscore agent' -Action $action -Trigger $trigger `
    -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName 'Cobra hiscore agent'
Write-Host "Installed. Log: $dest\agent.log"
