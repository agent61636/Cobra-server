# cobra-arcade, plain PowerShell as arcade:  powershell -ExecutionPolicy Bypass -File C:\Cobra\setup\05-displays.ps1
# Read-only. Prints the screens and the exact numbers for Big Box's marquee and Pinball FX's backglass/DMD windows (manual 11.6, 11.7).
. "$PSScriptRoot\common.ps1"
Add-Type -AssemblyName System.Windows.Forms
$all = [System.Windows.Forms.Screen]::AllScreens
$i = 0
foreach ($s in $all) { $i++; $b = $s.Bounds; Info ("screen {0} {1}: {2}x{3} at x={4} y={5}{6}" -f $i, $s.DeviceName, $b.Width, $b.Height, $b.X, $b.Y, $(if ($s.Primary) { '  <- main (cabinet screen)' } else { '' })) }
$main = $all | Where-Object Primary
$mq = $all | Where-Object { -not $_.Primary } | Select-Object -First 1
if (-not $mq) { Die 'only one screen. Plug in the marquee monitor, then Settings > System > Display > Extend these displays' }
$m = $mq.Bounds
if ($m.Y -ge 0) { Todo 'the marquee screen is not above the main screen. Settings > System > Display: drag it above screen 1' }
$dmdH = [int]($m.Height / 3)
Write-Host ''
Say 'Big Box: Options > General (or Views) > Marquee Screen'
Write-Host "    Marquee screen = $($mq.DeviceName)"
Say 'Pinball FX: Options > Cabinet Support'
Write-Host "    General:          cabinet mode ON"
Write-Host "    Backglass Window: position $($m.X), $($m.Y)   size $($m.Width), $($m.Height)"
Write-Host "    Dotmatrix Window: position $($m.X), $($m.Y + $m.Height - $dmdH)   size $($m.Width), $dmdH"
Say 'RetroArch: Settings > Video > Output > Monitor Index'
$idx = 0; $k = 0; foreach ($s in $all) { $k++; if ($s.Primary) { $idx = $k } }
Write-Host "    Monitor Index = $idx  (06-retroarch.ps1 -Apply sets it)"
