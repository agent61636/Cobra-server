# Shared helpers for the cabinet scripts. Dot-sourced, never run on its own.
$ErrorActionPreference = 'Stop'
$script:todo = 0
function Ok($m)   { Write-Host "  OK   $m" -ForegroundColor Green }
function Todo($m) { Write-Host " TODO  $m" -ForegroundColor Yellow; $script:todo++ }
function Info($m) { Write-Host "  ..   $m" -ForegroundColor Cyan }
function Say($m)  { Write-Host "==> $m" -ForegroundColor Green }
function Head($m) { Write-Host ""; Write-Host "== $m" -ForegroundColor White }
function Die($m)  { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

function Test-Admin {
  $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Keeps an existing file: renames it to <name>.bak-<time> before a new one is written.
function Backup-File($path) {
  if (Test-Path -LiteralPath $path) {
    $bak = "$path.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item -LiteralPath $path -Destination $bak
    Info "backed up $path -> $bak"
  }
}

function Find-First($paths) {
  foreach ($p in $paths) { if ($p -and (Test-Path -LiteralPath $p)) { return $p } }
  return $null
}

function Find-RetroArch {
  $exe = Find-First @('C:\RetroArch-Win64\retroarch.exe', 'C:\RetroArch\retroarch.exe', "$env:APPDATA\RetroArch\retroarch.exe", 'D:\RetroArch-Win64\retroarch.exe', 'D:\RetroArch\retroarch.exe')
  if ($exe) { return (Split-Path $exe) }
  return $null
}

function Find-LaunchBox {
  $exe = Find-First @('D:\LaunchBox\LaunchBox.exe', 'C:\LaunchBox\LaunchBox.exe', "$env:USERPROFILE\LaunchBox\LaunchBox.exe", 'D:\Games\LaunchBox\LaunchBox.exe')
  if ($exe) { return (Split-Path $exe) }
  return $null
}

function Find-LEDBlinky {
  return (Find-First @('C:\LEDBlinky\LEDBlinky.exe', 'D:\LEDBlinky\LEDBlinky.exe', "${env:ProgramFiles(x86)}\LEDBlinky\LEDBlinky.exe", "$env:ProgramFiles\LEDBlinky\LEDBlinky.exe"))
}

function Get-SteamLibraries {
  $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
  if (-not $steam) { return @() }
  $libs = @($steam -replace '/', '\')
  $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
  if (Test-Path $vdf) {
    foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) { $libs += ($m.Groups[1].Value -replace '\\\\', '\') }
  }
  return ($libs | Select-Object -Unique)
}

Add-Type -ErrorAction SilentlyContinue -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class CobraDisk {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern bool GetDiskFreeSpaceEx(string dir, out ulong free, out ulong total, out ulong totalFree);
  public static long Free(string dir) { ulong f, t, tf; return GetDiskFreeSpaceEx(dir, out f, out t, out tf) ? (long)f : -1; }
}
'@

function GB($bytes) { return [math]::Round($bytes / 1GB, 1) }
