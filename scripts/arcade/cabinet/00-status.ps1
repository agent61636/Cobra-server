# cobra-arcade, plain PowerShell as arcade:  powershell -ExecutionPolicy Bypass -File C:\Cobra\setup\00-status.ps1
# Read-only. Shows what's done on the cabinet and what's left. Changes nothing.
. "$PSScriptRoot\common.ps1"
$ErrorActionPreference = 'SilentlyContinue'

Head 'Windows'
if ($env:COMPUTERNAME -eq 'COBRA-ARCADE') { Ok 'computer name cobra-arcade' } else { Todo "computer name is $env:COMPUTERNAME (01-base.ps1 renames it)" }
if ($env:USERNAME -eq 'arcade') { Ok 'logged in as arcade' } else { Todo "logged in as $env:USERNAME; the cabinet runs as arcade" }
$lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" | Where-Object LicenseStatus -eq 1
if ($lic) { Ok 'Windows activated' } else { Todo 'Windows not activated (Settings > System > Activation)' }
$os = Get-CimInstance Win32_OperatingSystem
Info "$($os.Caption) build $($os.BuildNumber)"
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '10.6.9.*' }).IPAddress
if ($ip -contains '10.6.9.30') { Ok 'IP 10.6.9.30' } elseif ($ip) { Todo "IP is $ip, not 10.6.9.30 (OPNsense static mapping, manual 4.1)" } else { Todo 'no 10.6.9.x address: is the cable in cobra-switch port 3?' }
$wl = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
if ($wl.AutoAdminLogon -eq '1' -and $wl.DefaultUserName -eq 'arcade') { Ok 'auto-login as arcade' } else { Todo 'auto-login not set (01-base.ps1 opens Autologon)' }

Head 'Drives'
$d = Get-Volume -DriveLetter D
if ($d) {
  Ok "D: $($d.FileSystemLabel) $($d.FileSystem), $(GB $d.SizeRemaining) GB free of $(GB $d.Size) GB"
  Get-PhysicalDisk | ForEach-Object { if ($_.HealthStatus -eq 'Healthy') { Ok "disk $($_.FriendlyName): Healthy" } else { Todo "disk $($_.FriendlyName): $($_.HealthStatus)" } }
} else { Todo 'no D: drive (the 4 TB WD, manual 4.6)' }
$romsBytes = 0
if (Test-Path 'D:\Roms') {
  $plats = Get-ChildItem 'D:\Roms' -Directory
  foreach ($p in $plats) {
    $m = Get-ChildItem $p.FullName -Recurse -File | Measure-Object Length -Sum
    $romsBytes += [long]$m.Sum
    Info ("D:\Roms\{0,-28} {1,7} files {2,8} GB" -f $p.Name, $m.Count, (GB $m.Sum))
  }
  Ok "D:\Roms: $($plats.Count) platform folders, $(GB $romsBytes) GB"
} else { Todo 'no D:\Roms folder (01-base.ps1 makes it)' }

Head 'Apps'
$ra = Find-RetroArch
if ($ra) { Ok "RetroArch: $ra" } else { Todo 'RetroArch not found (01-base.ps1 installs it)' }
if ($ra) { foreach ($s in 'saves', 'states', 'system', 'config', 'playlists') { if (-not (Test-Path "$ra\$s")) { Info "RetroArch\$s not there yet (it appears after the first launch)" } } }
$lb = Find-LaunchBox
if ($lb) { Ok "LaunchBox: $lb" } else { Todo 'LaunchBox not found (installer from launchbox-app.com)' }
if ($lb -and (Test-Path "$lb\BigBox.exe")) { Ok 'Big Box present' }
$led = Find-LEDBlinky
if ($led) { Ok "LEDBlinky: $led" } else { Todo 'LEDBlinky not installed (ledblinky.net, to C:\LEDBlinky)' }
$libs = Get-SteamLibraries
if ($libs.Count) { Ok "Steam libraries: $($libs -join ', ')" } else { Todo 'Steam not installed (01-base.ps1 installs it)' }
$pfx = $null
foreach ($l in $libs) { $c = Get-ChildItem "$l\steamapps\common" -Directory | Where-Object Name -like 'Pinball FX*' | Select-Object -First 1; if ($c) { $pfx = $c.FullName } }
if ($pfx) { Ok "Pinball FX: $pfx" } else { Info 'Pinball FX not installed in Steam yet' }

Head 'Hardware'
$wiz = Get-PnpDevice -PresentOnly | Where-Object InstanceId -match 'VID_FAFA'
if ($wiz) { $wiz | ForEach-Object { Ok "LED-Wiz: $($_.FriendlyName) [$($_.Status)] $($_.InstanceId)" } } else { Todo 'LED-Wiz (USB VID_FAFA) not seen: check its USB cable' }
$pads = Get-PnpDevice -PresentOnly | Where-Object { $_.FriendlyName -match 'Xbox|XINPUT|X-Arcade|game controller' }
if ($pads) { $pads | ForEach-Object { Ok "controller: $($_.FriendlyName) [$($_.Status)]" } } else { Todo 'no Xbox-mode controller seen: Tankstick mode switch / USB' }
Get-PnpDevice -PresentOnly -Class Mouse | ForEach-Object { Info "mouse/trackball: $($_.FriendlyName) [$($_.Status)]" }
Get-CimInstance Win32_VideoController | ForEach-Object { Info "GPU: $($_.Name), driver $($_.DriverVersion)" }
Add-Type -AssemblyName System.Windows.Forms
$screens = [System.Windows.Forms.Screen]::AllScreens
foreach ($s in $screens) { $b = $s.Bounds; Info ("screen {0}: {1}x{2} at {3},{4}{5}" -f $s.DeviceName, $b.Width, $b.Height, $b.X, $b.Y, $(if ($s.Primary) { ' (main)' } else { '' })) }
if ($screens.Count -ge 2) { Ok "$($screens.Count) screens (marquee connected)" } else { Todo 'only one screen: marquee monitor not connected or not extended' }

Head 'SGIN shares and nightly copy'
if (Test-Connection cobra-stream -Count 1 -Quiet) { Ok 'cobra-stream answers ping' } else { Todo 'cobra-stream does not answer (SGIN off, or DNS)' }
if ((cmdkey /list) -match 'cobra-stream') { Ok 'saved share login for cobra-stream' } else { Todo 'no saved share login (cmdkey step in the runbook)' }
$rr = Test-Path '\\cobra-stream\roms'; $mm = Test-Path '\\cobra-stream\media'
if ($rr) { Ok '\\cobra-stream\roms reachable' } else { Todo '\\cobra-stream\roms not reachable' }
if ($mm) { Ok '\\cobra-stream\media reachable' } else { Todo '\\cobra-stream\media not reachable' }
if ($rr) {
  $free = [CobraDisk]::Free('\\cobra-stream\roms\')
  if ($free -ge 0) {
    Info "dock1b free: $(GB $free) GB"
    if ($romsBytes -gt $free) { Todo "D:\Roms ($(GB $romsBytes) GB) is bigger than dock1b's free space: the first copy will not fit. Stop and decide before running the nightly copy" }
  }
}
$t = Get-ScheduledTask -TaskName 'Cobra nightly copy'
if ($t) { $i = $t | Get-ScheduledTaskInfo; Ok "task 'Cobra nightly copy': last run $($i.LastRunTime), result $($i.LastTaskResult), next $($i.NextRunTime)" } else { Todo "task 'Cobra nightly copy' not registered (02-nightly.ps1)" }
if (Test-Path 'C:\Cobra\nightly-copy.log') {
  $errs = Select-String -Path 'C:\Cobra\nightly-copy.log' -Pattern 'ERROR' | Select-Object -Last 5
  if ($errs) { Todo 'nightly-copy.log has ERROR lines (last 5):'; $errs | ForEach-Object { Info $_.Line } } else { Ok 'nightly-copy.log has no ERROR lines' }
}
if (Get-NetFirewallRule -DisplayName 'RetroArch netplay') { Ok 'firewall: RetroArch netplay rule' } else { Todo 'firewall: no RetroArch netplay rule (01-base.ps1)' }

Write-Host ""
if ($script:todo -eq 0) { Say 'Nothing left on this list.' } else { Write-Host "$($script:todo) TODO line(s)." -ForegroundColor Yellow }
