# cobra-arcade, PowerShell AS ADMINISTRATOR:  powershell -ExecutionPolicy Bypass -File C:\Cobra\setup\01-base.ps1
# Name, apps (only the missing ones), power, netplay firewall rule, folders, auto-login. Deletes and formats nothing.
. "$PSScriptRoot\common.ps1"
if (-not (Test-Admin)) { Die 'run this from an Administrator PowerShell (right-click Terminal > Run as administrator)' }
$reboot = $false

Say 'computer name'
if ($env:COMPUTERNAME -ne 'COBRA-ARCADE') { Rename-Computer -NewName cobra-arcade -Force; $reboot = $true; Ok 'renamed to cobra-arcade (after the reboot)' } else { Ok 'already cobra-arcade' }

Say 'apps (winget)'
foreach ($id in 'Valve.Steam', 'Libretro.RetroArch', 'Microsoft.Sysinternals.Autologon') {
  winget list -e --id $id --accept-source-agreements *> $null
  if ($LASTEXITCODE -eq 0) { Ok "$id already installed" }
  else {
    Info "installing $id"
    winget install -e --id $id --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -eq 0) { Ok "$id installed" } else { Todo "$id failed (exit $LASTEXITCODE): run  winget install -e --id $id" }
  }
}

Say 'power: never sleep, screen never off (on AC)'
powercfg /change standby-timeout-ac 0
powercfg /change monitor-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
Ok 'set'

Say 'firewall: RetroArch netplay TCP 55435 from LAN and WireGuard'
if (Get-NetFirewallRule -DisplayName 'RetroArch netplay' -ErrorAction SilentlyContinue) { Ok 'rule already there' }
else { New-NetFirewallRule -DisplayName 'RetroArch netplay' -Direction Inbound -Protocol TCP -LocalPort 55435 -RemoteAddress 10.6.9.0/24, 10.6.99.0/24 -Action Allow -Profile Any | Out-Null; Ok 'rule added' }

Say 'folders'
foreach ($f in 'C:\Cobra', 'C:\Cobra\setup') { if (-not (Test-Path $f)) { New-Item -ItemType Directory $f | Out-Null; Ok "made $f" } else { Ok "$f exists" } }
if (Test-Path 'D:\') {
  if (-not (Test-Path 'D:\Roms')) { New-Item -ItemType Directory 'D:\Roms' | Out-Null; Ok 'made D:\Roms' } else { Ok 'D:\Roms exists (left as it is)' }
} else { Todo 'no D: drive; D:\Roms not made' }
$acl = Get-Acl 'C:\Cobra'
if (-not ($acl.Access | Where-Object { $_.IdentityReference -match '\\arcade$' -and $_.FileSystemRights -match 'Modify|FullControl' })) {
  icacls C:\Cobra /grant 'arcade:(OI)(CI)M' | Out-Null; Ok 'arcade can write C:\Cobra'
}

Say 'auto-login as arcade'
$wl = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
if ($wl.AutoAdminLogon -eq '1' -and $wl.DefaultUserName -eq 'arcade') { Ok 'already set' }
else {
  $al = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages", "$env:ProgramFiles\WinGet\Packages" -Recurse -Filter Autologon64.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($al) { Info 'Autologon is opening: Username arcade, Domain cobra-arcade, the arcade password, then Enable'; Start-Process $al.FullName -ArgumentList '/accepteula' -Wait }
  else { Todo 'Autologon64.exe not found: open a new Terminal and run  autologon64' }
}

Write-Host ''
if ($reboot) { Say 'Reboot needed for the new name:  Restart-Computer' } else { Say 'Done. No reboot needed.' }
