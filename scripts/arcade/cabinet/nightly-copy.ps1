# Nightly copies for cobra-arcade (manual 4.5 / 4.6). Run by the task 'Cobra nightly copy' as arcade.
# robocopy /E /XO adds and updates, never deletes, never replaces a newer file.
$log = 'C:\Cobra\nightly-copy.log'
$media = '\\cobra-stream\media'
$ra = @('C:\RetroArch-Win64', 'C:\RetroArch', "$env:APPDATA\RetroArch") | Where-Object { Test-Path "$_\retroarch.exe" } | Select-Object -First 1
$lb = @('D:\LaunchBox', 'C:\LaunchBox', "$env:USERPROFILE\LaunchBox") | Where-Object { Test-Path "$_\LaunchBox.exe" } | Select-Object -First 1
$bk = "$media\dock1a\backups\arcade"

# 1) cabinet -> SGIN
$up = [ordered]@{}
if ($ra) { foreach ($s in 'saves', 'states', 'system', 'config', 'playlists') { $up["$ra\$s"] = "$bk\RetroArch\$s" } }
if ($lb) { $up["$lb\Data"] = "$bk\LaunchBox\Data" }
$up['C:\Cobra'] = "$bk\Cobra"
$up['D:\Roms'] = '\\cobra-stream\roms'
# 2) SGIN -> D:\Cobra-copy (the folders you'd hate to lose; not roms, their main copy is D:\Roms)
$down = 'dock1a\music', 'dock1a\audiobooks', 'dock1a\books', 'dock1a\comics', 'dock1a\scans', 'dock1a\backups'

function Copy-One($src, $dst) {
  if (-not (Test-Path -LiteralPath $src)) { Add-Content $log "skip (missing): $src"; return }
  robocopy $src $dst /E /XO /R:2 /W:5 /NP /NFL /NDL /XF '*.log' /LOG+:$log | Out-Null
  if ($LASTEXITCODE -ge 8) { Add-Content $log "ERROR robocopy $LASTEXITCODE : $src -> $dst" }
}

Add-Content $log "=== start $(Get-Date)"
if (-not (Test-Path '\\cobra-stream\roms')) { Add-Content $log 'ERROR \\cobra-stream\roms not reachable (SGIN off, or no saved login: cmdkey /list)'; exit 1 }
foreach ($k in $up.Keys) { Copy-One $k $up[$k] }
if (Test-Path 'D:\') { foreach ($f in $down) { Copy-One "$media\$f" "D:\Cobra-copy\$f" } }
Add-Content $log "=== end $(Get-Date)"
