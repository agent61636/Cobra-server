# cobra-arcade, plain PowerShell as arcade:  powershell -ExecutionPolicy Bypass -File C:\Cobra\setup\04-ledwiz-test.ps1
# Lights LED-Wiz ports 1-32 one at a time and records what lit, into C:\Cobra\ledwiz-portmap.csv (manual 11.2).
# At each port type what lit (e.g. P1 B1 red), Enter = nothing lit, r = light it again, q = stop.
param([int]$From = 1, [int]$To = 32)
. "$PSScriptRoot\common.ps1"
$wiz = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object InstanceId -match 'VID_FAFA'
if (-not $wiz) { Die 'LED-Wiz not seen (USB VID_FAFA). Try another USB port/cable; Device Manager > Human Interface Devices' }
Ok "LED-Wiz: $(@($wiz)[0].InstanceId)"
$lb = Find-LEDBlinky
if (-not $lb) { Die 'LEDBlinky.exe not found. Install it to C:\LEDBlinky first (ledblinky.net)' }
Ok "LEDBlinky: $lb"
if (Get-Process LaunchBox, BigBox -ErrorAction SilentlyContinue) { Die 'close LaunchBox / Big Box first, they drive the LEDs too' }

function Set-Port($p, $lvl) { & $lb 14 "$p,$lvl" | Out-Null; Start-Sleep -Milliseconds 150 }
Say 'all ports off'
1..32 | ForEach-Object { Set-Port $_ 0 }

$csv = 'C:\Cobra\ledwiz-portmap.csv'
Backup-File $csv
$rows = @()
for ($p = $From; $p -le $To; $p++) {
  Set-Port $p 48
  $a = Read-Host "port $p lit. What lit? (Enter = nothing, r = again, q = stop)"
  Set-Port $p 0
  if ($a -eq 'q') { break }
  if ($a -eq 'r') { $p--; continue }
  if ([string]::IsNullOrWhiteSpace($a)) { $a = '(nothing)' }
  $rows += [pscustomobject]@{ Port = $p; Lit = $a }
}
$rows | Export-Csv $csv -NoTypeInformation
Ok "saved $csv"
$rows | Format-Table -AutoSize
$dark = @($rows | Where-Object Lit -eq '(nothing)').Count
Info "$($rows.Count - $dark) ports lit something, $dark lit nothing"
