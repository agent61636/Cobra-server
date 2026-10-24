# Cobra hiscore plugin (LaunchBox and Big Box)

A LaunchBox plugin for the cabinet. When a game played through an emulator (RetroArch, MAME) closes, it:

1. finds the `.hi` files the game wrote and uploads them to `scores.songofeo.com` straight away, so the arcade screen shows the score seconds after you quit;
2. sends the game's **proper title and platform** from LaunchBox, so the board says "Galaga" instead of `galaga`;
3. if **hi2txt** is installed on the cabinet, reads the score table (rank, initials, score) and sends that too, so the board and the arcade screen show real tables.

It works alongside the hiscore agent (`apps/hiscore-agent`), not instead of it. The agent still catches games started outside LaunchBox and retries uploads when the network is down. The server ignores a file it already has, so the two never double-count.

- Uses the agent's settings: the server address and watched folders from `C:\Cobra\hiscore-agent\config.json`, and the API key from its `key.dat` (encrypted for the `arcade` Windows user; the plugin runs as that user inside LaunchBox).
- Never slows down LaunchBox: the work runs in the background after the game closes, and errors only go to `plugin.log`.
- Details that can't be sent (network down) wait in `pending.json` and go with the next game.

## Build

On the cabinet or any Windows PC with LaunchBox and the [.NET 8 SDK](https://dotnet.microsoft.com/download):

```powershell
cd apps\hiscore-launchbox
dotnet build -c Release -p:LaunchBoxDir=D:\LaunchBox     # your LaunchBox folder
```

It compiles against LaunchBox's own `Core\Unbroken.LaunchBox.Plugins.dll`. The result is `bin\Release\net6.0\CobraHiscore.dll`. If the build warns "built against test stand-ins", the LaunchBox folder was wrong: don't install that build.

The plugin targets .NET 6, which every LaunchBox 13.x loads (newer LaunchBox releases on a newer .NET load it too).

## Install (as `arcade`)

1. Set up the hiscore agent first (manual 7.5). The plugin needs its `config.json` and `key.dat`.
2. Close LaunchBox and Big Box.
3. Make the folder `D:\LaunchBox\Plugins\CobraHiscore\` and copy in `CobraHiscore.dll` and `config.example.json`, renamed to `config.json`.
4. If Windows marked the DLL as downloaded: right-click → Properties → **Unblock**.
5. Start LaunchBox. Play a game, set a score, quit. `Plugins\CobraHiscore\plugin.log` shows `uploaded fbneo/galaga.hi (201)` and `sent details for fbneo/galaga.hi (200)`.

## Readable score tables with hi2txt (optional)

hi2txt (by GreatStone) knows the score layout of many arcade games. It is freeware for Windows, not open source, so it isn't included here: read its license before using it, and download it yourself.

1. Unzip hi2txt to `C:\Cobra\hi2txt\`.
2. In the plugin's `config.json`, set `"hi2txt"` to `hi2txt.exe` and list each core's `hiscore.dat` under `"hiscoreDat"` (the example has FinalBurn Neo and MAME 2003-Plus).
3. Test one game by hand first, from PowerShell:
   ```powershell
   C:\Cobra\hi2txt\hi2txt.exe -hiscoredat C:\RetroArch-Win64\system\fbneo\hiscore.dat -r C:\RetroArch-Win64\saves\fbneo\hi\galaga.hi
   ```
   It should print a table with a header such as `RANK|SCORE|NAME`. If your hi2txt version wants other options, set `"hi2txtArgs"` in `config.json`, for example `["-r", "{file}"]`. `{file}`, `{dat}`, `{game}` and `{system}` are filled in for each game.

The plugin sends hi2txt's text as it is, and the server reads it (it takes the first table that has a score column). Games hi2txt doesn't know still show on the board as "score table saved".

## Tests

`dotnet test tests\CobraHiscore.Tests.csproj` (CI runs it on Windows). The tests build against small stand-ins for LaunchBox's API in `stubs\`.
