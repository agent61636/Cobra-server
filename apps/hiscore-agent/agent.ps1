<#
.SYNOPSIS
  Cobra hiscore agent for the arcade cabinet. Uploads every changed .hi file
  to scores.songofeo.com, so the board always shows the newest scores.

.DESCRIPTION
  Every few seconds it looks at the folders in config.json for *.hi files.
  A file that changed (new size, time or contents) and has stopped changing
  for a few seconds is uploaded with the cabinet's API key. If the upload
  fails (network down, gate off), the file simply stays "changed" and is
  retried on the next pass, so nothing is lost while the server is away.

  Works in Windows PowerShell 5.1 (built into Windows 11); no install needed.

.EXAMPLE
  .\agent.ps1 -SetKey      # once: store the API key, encrypted for this Windows user
  .\agent.ps1 -Once        # one pass, then exit (for testing)
  .\agent.ps1              # run forever (what the scheduled task does)
#>
[CmdletBinding()]
param(
    [switch]$SetKey,
    [switch]$Once,
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json')
)

$ErrorActionPreference = 'Stop'
$AgentDir  = Split-Path -Parent $ConfigPath
$KeyPath   = Join-Path $AgentDir 'key.dat'
$StatePath = Join-Path $AgentDir 'state.json'
$LogPath   = Join-Path $AgentDir 'agent.log'

function Write-Log([string]$Message) {
    $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Message
    try {
        if ((Test-Path $LogPath) -and (Get-Item $LogPath).Length -gt 1MB) {
            Move-Item $LogPath ($LogPath + '.1') -Force
        }
        Add-Content -Path $LogPath -Value $line
    } catch { }
    Write-Verbose $line
}

function Get-ApiKey {
    if ($env:COBRA_HISCORE_KEY) { return $env:COBRA_HISCORE_KEY }   # testing only
    if (-not (Test-Path $KeyPath)) { throw "No API key yet. Run: .\agent.ps1 -SetKey" }
    $secure = Get-Content $KeyPath | ConvertTo-SecureString            # DPAPI: only this Windows user can read it
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

if ($SetKey) {
    $secure = Read-Host -AsSecureString 'Paste the cabinet API key'
    $secure | ConvertFrom-SecureString | Set-Content -Path $KeyPath
    Write-Host "Key saved to $KeyPath (readable only by $env:USERNAME on this PC)."
    return
}

function Read-Config {
    $c = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    if (-not $c.server) { throw "config.json: 'server' is missing" }
    if (-not $c.folders) { throw "config.json: 'folders' is missing" }
    if (-not $c.intervalSeconds) { $c | Add-Member -NotePropertyName intervalSeconds -NotePropertyValue 15 }
    if (-not $c.settleSeconds)   { $c | Add-Member -NotePropertyName settleSeconds   -NotePropertyValue 5 }
    return $c
}

function Read-State {
    $state = @{}
    if (Test-Path $StatePath) {
        $obj = Get-Content $StatePath -Raw | ConvertFrom-Json
        foreach ($p in $obj.PSObject.Properties) { $state[$p.Name] = $p.Value.sha256 }
    }
    return $state
}

function Save-State($state) {
    $out = [ordered]@{}
    foreach ($k in ($state.Keys | Sort-Object)) { $out[$k] = @{ sha256 = $state[$k] } }
    $tmp = $StatePath + '.tmp'
    ($out | ConvertTo-Json -Depth 3) | Set-Content -Path $tmp -Encoding UTF8
    Move-Item $tmp $StatePath -Force
}

function ConvertTo-Segment([string]$s) {
    # The server accepts letters, digits, '.', '_' and '-' (max 64), starting with a letter or digit.
    $clean = ($s -replace '[^A-Za-z0-9._-]', '_').Trim('._-')
    if ($clean.Length -gt 64) { $clean = $clean.Substring(0, 64) }
    if (-not $clean) { $clean = 'unknown' }
    return $clean
}

function Get-SystemName($folder, [IO.FileInfo]$file) {
    # A folder can name its system outright; "auto" uses the first subfolder under it
    # (RetroArch keeps each core's files in their own folder, e.g. saves\fbneo\...).
    if ($folder.system -and $folder.system -ne 'auto') { return (ConvertTo-Segment $folder.system) }
    $root = (Resolve-Path $folder.path).Path.TrimEnd('\', '/')
    $rel = $file.DirectoryName.Substring([Math]::Min($root.Length, $file.DirectoryName.Length)).TrimStart('\', '/')
    $first = ($rel -split '[\\/]')[0]
    if ($first) { return (ConvertTo-Segment $first) }
    return 'retroarch'
}

function Send-HiFile($config, [string]$apiKey, [string]$system, [IO.FileInfo]$file) {
    $name = ConvertTo-Segment $file.Name
    $url = '{0}/upload/{1}/{2}' -f $config.server.TrimEnd('/'), [Uri]::EscapeDataString($system), [Uri]::EscapeDataString($name)
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    $headers = @{
        Authorization  = "Bearer $apiKey"
        'X-File-Mtime' = $file.LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
        'X-Source'     = ConvertTo-Segment $env:COMPUTERNAME
    }
    $r = Invoke-WebRequest -Uri $url -Method Put -Body $bytes -ContentType 'application/octet-stream' `
        -Headers $headers -UseBasicParsing -TimeoutSec 20
    return [int]$r.StatusCode
}

function Invoke-Pass($config, [string]$apiKey, $state) {
    $now = [DateTime]::UtcNow
    $dirty = $false
    foreach ($folder in $config.folders) {
        if (-not (Test-Path $folder.path)) { continue }
        foreach ($file in Get-ChildItem -Path $folder.path -Filter '*.hi' -Recurse -File -ErrorAction SilentlyContinue) {
            if (($now - $file.LastWriteTimeUtc).TotalSeconds -lt $config.settleSeconds) { continue }  # still being written
            try { $sha = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash.ToLower() }
            catch { continue }   # locked by the emulator right now; next pass
            $system = Get-SystemName $folder $file
            $id = "$system/$($file.Name)"
            if ($state[$id] -eq $sha) { continue }
            try {
                $code = Send-HiFile $config $apiKey $system $file
                Write-Log "uploaded $id ($code)"
                $state[$id] = $sha
                $dirty = $true
            } catch {
                Write-Log "will retry $id : $($_.Exception.Message)"
            }
        }
    }
    if ($dirty) { Save-State $state }
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$config = Read-Config
$apiKey = Get-ApiKey
$state = Read-State
Write-Log "agent started; watching $(@($config.folders).Count) folder(s); server $($config.server)"
do {
    try { Invoke-Pass $config $apiKey $state }
    catch { Write-Log "pass failed: $($_.Exception.Message)" }
    if (-not $Once) { Start-Sleep -Seconds $config.intervalSeconds }
} while (-not $Once)
