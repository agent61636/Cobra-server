# cobra-arcade, plain PowerShell as arcade:  powershell -ExecutionPolicy Bypass -File C:\Cobra\setup\06-retroarch.ps1
# Shows the RetroArch settings the cabinet needs. With -Apply: backs up retroarch.cfg, then sets them (manual 11.6, 11.8).
param([switch]$Apply)
. "$PSScriptRoot\common.ps1"
$ra = Find-RetroArch
if (-not $ra) { Die 'RetroArch not found' }
$cfg = "$ra\retroarch.cfg"
if (-not (Test-Path $cfg)) { Die "$cfg is missing: start RetroArch once and quit it" }

Add-Type -AssemblyName System.Windows.Forms
$idx = 0; $k = 0; foreach ($s in [System.Windows.Forms.Screen]::AllScreens) { $k++; if ($s.Primary) { $idx = $k } }
$nvidia = [bool](Get-CimInstance Win32_VideoController | Where-Object Name -match 'NVIDIA')
$want = [ordered]@{
  'video_fullscreen'          = 'true'
  'video_windowed_fullscreen' = 'true'
  'video_monitor_index'       = "$idx"
  'pause_nonactive'           = 'false'
  'menu_driver'               = 'ozone'
}
if ($nvidia) { $want['video_driver'] = 'vulkan' } else { Info 'no NVIDIA card yet: video_driver left as it is (vulkan after the RTX 3050, manual 4.7)' }

$text = Get-Content $cfg
$change = 0
foreach ($key in $want.Keys) {
  $line = $text | Where-Object { $_ -match "^$key\s*=" } | Select-Object -First 1
  $now = if ($line) { ($line -split '=', 2)[1].Trim().Trim('"') } else { '(not set)' }
  if ($now -eq $want[$key]) { Ok "$key = $now" } else { Todo "$key = $now  (want $($want[$key]))"; $change++ }
}
if (-not $Apply) { if ($change) { Write-Host ''; Say "run again with -Apply to set these $change value(s)" }; exit 0 }
if ($change -eq 0) { Say 'nothing to change'; exit 0 }
if (Get-Process retroarch -ErrorAction SilentlyContinue) { Die 'close RetroArch first: it rewrites retroarch.cfg when it quits' }
Backup-File $cfg
foreach ($key in $want.Keys) {
  $new = "$key = `"$($want[$key])`""
  if ($text -match "^$key\s*=") { $text = $text -replace "^$key\s*=.*$", $new } else { $text += $new }
}
Set-Content -Path $cfg -Value $text -Encoding ascii
Say "set $change value(s) in $cfg"
