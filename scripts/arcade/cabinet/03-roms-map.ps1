# cobra-arcade, plain PowerShell as arcade:  powershell -ExecutionPolicy Bypass -File C:\Cobra\setup\03-roms-map.ps1
# Reads the folder names in D:\Roms (renames nothing) and writes RomM's folder map:
#   C:\Cobra\romm-platforms.yml  and a copy in \\cobra-stream\media\dock1a\backups\arcade\  (romm-up.sh / romm-platforms.sh read it)
. "$PSScriptRoot\common.ps1"
if (-not (Test-Path 'D:\Roms')) { Die 'no D:\Roms' }

# RomM slugs (IGDB style). Folders already named like a slug need no line.
$slugs = 'arcade','nes','famicom','fds','snes','n64','ngc','wii','gb','gbc','gba','nds','virtualboy','sms','gamegear',
  'genesis-slash-megadrive','segacd','sega32','saturn','dc','ps','ps2','psp','turbografx16--1','turbografx-16-slash-pc-engine-cd','atari2600','atari5200',
  'atari7800','lynx','jaguar','colecovision','intellivision','vectrex','neogeoaes','neogeomvs','neo-geo-cd','neo-geo-pocket','neo-geo-pocket-color',
  'wonderswan','wonderswan-color','msx','c64','amiga','dos','3do','pc-fx','pokemon-mini','n3ds'
# Common other names (LaunchBox, RetroArch, No-Intro, EmulationStation) -> slug. Lower-case, spaces/punctuation dropped.
$alias = @{
  'mame'='arcade'; 'mame2003'='arcade'; 'mame2003plus'='arcade'; 'fbneo'='arcade'; 'finalburnneo'='arcade'; 'fba'='arcade'; 'cps1'='arcade'; 'cps2'='arcade'; 'cps3'='arcade'
  'supernes'='snes'; 'nintendosnes'='snes'; 'supernintendosnes'='snes'; 'supernessnes'='snes'; 'nintendones'='nes'; 'famicomnes'='nes'
  'segagenesismegadrive'='genesis-slash-megadrive'; 'genesismegadrive'='genesis-slash-megadrive'; 'megadrivegenesis'='genesis-slash-megadrive'
  'nintendogamecubegc'='ngc'; 'nintendo3ds'='n3ds'; '3ds'='n3ds'; 'turbografx'='turbografx16--1'; 'arcademame'='arcade'; 'segamegacd'='segacd'; 'segacd32x'='sega32'
  'nintendoentertainmentsystem'='nes'; 'famicomdisksystem'='fds'
  'supernintendo'='snes'; 'supernintendoentertainmentsystem'='snes'; 'superfamicom'='snes'; 'sfc'='snes'
  'nintendo64'='n64'; 'gamecube'='ngc'; 'nintendogamecube'='ngc'; 'gc'='ngc'; 'nintendowii'='wii'
  'gameboy'='gb'; 'nintendogameboy'='gb'; 'gameboycolor'='gbc'; 'nintendogameboycolor'='gbc'; 'gameboyadvance'='gba'; 'nintendogameboyadvance'='gba'
  'nintendods'='nds'; 'ds'='nds'; 'nintendovirtualboy'='virtualboy'; 'vb'='virtualboy'
  'mastersystem'='sms'; 'segamastersystem'='sms'; 'segagamegear'='gamegear'; 'gg'='gamegear'
  'genesis'='genesis-slash-megadrive'; 'segagenesis'='genesis-slash-megadrive'; 'megadrive'='genesis-slash-megadrive'; 'segamegadrive'='genesis-slash-megadrive'; 'md'='genesis-slash-megadrive'
  'segacd'='segacd'; 'megacd'='segacd'; 'sega32x'='sega32'; '32x'='sega32'; 'segasaturn'='saturn'; 'dreamcast'='dc'; 'segadreamcast'='dc'
  'psx'='ps'; 'playstation'='ps'; 'sonyplaystation'='ps'; 'ps1'='ps'; 'psone'='ps'; 'playstation2'='ps2'; 'sonyplaystation2'='ps2'; 'playstationportable'='psp'; 'sonypsp'='psp'
  'pcengine'='turbografx16--1'; 'turbografx16'='turbografx16--1'; 'necturbografx16'='turbografx16--1'; 'pce'='turbografx16--1'; 'pcenginecd'='turbografx-16-slash-pc-engine-cd'; 'turbografxcd'='turbografx-16-slash-pc-engine-cd'
  'atari2600'='atari2600'; 'atari5200'='atari5200'; 'atari7800'='atari7800'; 'atarilynx'='lynx'; 'atarijaguar'='jaguar'
  'neogeo'='arcade'; 'snkneogeo'='arcade'; 'neogeoaes'='neogeoaes'; 'neogeomvs'='neogeomvs'; 'neogeocd'='neo-geo-cd'
  'neogeopocket'='neo-geo-pocket'; 'neogeopocketcolor'='neo-geo-pocket-color'; 'bandaiwonderswan'='wonderswan'; 'wonderswancolor'='wonderswan-color'; 'wsc'='wonderswan-color'
  'commodore64'='c64'; 'commodoreamiga'='amiga'; 'msdos'='dos'; 'pc'='dos'; 'panasonic3do'='3do'; 'mattelintellivision'='intellivision'; 'gcevectrex'='vectrex'
}

$lines = @(); $unknown = @()
foreach ($f in Get-ChildItem 'D:\Roms' -Directory | Sort-Object Name) {
  $n = $f.Name; $key = ($n.ToLower() -replace '[^a-z0-9]', '')
  if ($slugs -contains $n.ToLower()) { Ok "$n  (already a RomM name)"; continue }
  if ($alias.ContainsKey($key)) { $lines += "  `"$n`": `"$($alias[$key])`""; Ok "$n  -> $($alias[$key])"; continue }
  $unknown += $n; Todo "$n  (unknown: RomM shows it as its own platform; pick one at docs.romm.app > Supported platforms and add it to the file)"
}

$out = 'C:\Cobra\romm-platforms.yml'
$body = @('# RomM folder map from cobra-arcade D:\Roms. Key = folder name, value = RomM platform slug.', 'platforms:') + $lines
if ($unknown) { $body += $unknown | ForEach-Object { "  # `"$_`": `"<slug>`"" } }
if ($lines.Count -eq 0 -and -not $unknown) { Say 'every folder is already a RomM name: no map needed'; exit 0 }
Backup-File $out
Set-Content -Path $out -Value $body -Encoding ascii
Ok "wrote $out"
$share = '\\cobra-stream\media\dock1a\backups\arcade'
if (Test-Path '\\cobra-stream\media') {
  if (-not (Test-Path $share)) { New-Item -ItemType Directory $share -Force | Out-Null }
  Backup-File "$share\romm-platforms.yml"
  Copy-Item $out "$share\romm-platforms.yml" -Force
  Ok "copied to $share\romm-platforms.yml"
} else { Todo '\\cobra-stream\media not reachable: copy it later' }
Get-Content $out
