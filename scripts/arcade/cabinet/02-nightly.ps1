# cobra-arcade, plain PowerShell as arcade (NOT admin):  powershell -ExecutionPolicy Bypass -File C:\Cobra\setup\02-nightly.ps1
# Puts nightly-copy.ps1 in C:\Cobra and registers the 3:30 am task. Add -RunNow to start the first copy now.
param([switch]$RunNow)
. "$PSScriptRoot\common.ps1"
if ($env:USERNAME -ne 'arcade') { Die "log in as arcade first (you are $env:USERNAME): the task and the share login belong to arcade" }
if (-not ((cmdkey /list) -match 'cobra-stream')) { Die 'no saved login for cobra-stream yet. Run:  cmdkey /add:cobra-stream /user:arcade /pass' }
if (-not (Test-Path '\\cobra-stream\roms')) { Die '\\cobra-stream\roms is not reachable. Is the SGIN on? Run 00-status.ps1' }

$src = "$PSScriptRoot\nightly-copy.ps1"; $dst = 'C:\Cobra\nightly-copy.ps1'
if (-not (Test-Path $dst)) { Copy-Item $src $dst; Ok "installed $dst" }
elseif ((Get-FileHash $src).Hash -eq (Get-FileHash $dst).Hash) { Ok "$dst already up to date" }
else { Copy-Item $src "$dst.new" -Force; Todo "$dst already exists and differs: kept it, saved the new one as $dst.new. Compare them, then: Move-Item $dst.new $dst -Force" }

$romsBytes = (Get-ChildItem 'D:\Roms' -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
$free = [CobraDisk]::Free('\\cobra-stream\roms\')
Info "D:\Roms $(GB $romsBytes) GB, dock1b free $(GB $free) GB"
if ($free -ge 0 -and $romsBytes -gt $free) { Die 'D:\Roms is bigger than the free space on dock1b. Not registering the task. Decide which platforms go to the web arcade first.' }

if (Get-ScheduledTask -TaskName 'Cobra nightly copy' -ErrorAction SilentlyContinue) { Ok "task 'Cobra nightly copy' already registered (left as it is)" }
else {
  $a = New-ScheduledTaskAction -Execute powershell.exe -Argument '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\Cobra\nightly-copy.ps1'
  $t = New-ScheduledTaskTrigger -Daily -At 3:30am
  $s = New-ScheduledTaskSettingsSet -WakeToRun -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 12)
  Register-ScheduledTask -TaskName 'Cobra nightly copy' -Action $a -Trigger $t -Settings $s | Out-Null
  Ok "registered 'Cobra nightly copy' daily 3:30 am"
}
if ($RunNow) { Start-ScheduledTask 'Cobra nightly copy'; Say 'first copy started in the background. Watch it:  Get-Content C:\Cobra\nightly-copy.log -Tail 20 -Wait' }
