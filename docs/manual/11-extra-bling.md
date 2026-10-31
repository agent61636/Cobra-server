# 11. Extra bling: lit buttons, marquee screen, pinball backglass and CRT bezels

**Result:** on the cabinet (`cobra-arcade`, part 4), the Tankstick's buttons and trackball light up in each game's colors: the real arcade panel colors for arcade games, and a color set per console for everything else. The small VGA monitor above the screen shows the selected game's marquee. In Pinball FX it becomes the backglass with the dot-matrix display (DMD). RetroArch games get a CRT look with a bezel whose color matches the buttons.

**Needs:** part 4 done: Big Box boots, games launch from it, and the Tankstick is mapped. About an evening, most of it the LED wiring test (11.2) and choosing colors.

**What you have** (so nothing here has to be asked again):

| Part | What it is |
|---|---|
| Controls | X-Arcade Tankstick with trackball, the 2-player version: two 8-button player panels, 1P and 2P start, the P3 button, the 2 side buttons, and the trackball. Every button is mapped as a standard Xbox controller |
| LED controller | An **LED-Wiz** board (GroovyGameGear) wired into the Tankstick, on USB to the OptiPlex |
| Marquee screen | A small old VGA monitor, the cabinet's second display |
| Pinball | Pinball FX (Steam), with its cabinet mode |

Everything in this part runs on the cabinet, logged in as `arcade`. Nothing on the servers changes.

---

## 11.1 How the lighting works, and one limit to know first

- **The LED-Wiz** has **32 outputs**. Each output switches one LED (or one color of an RGB LED) on, at 48 brightness levels, with up to 500 mA per output. It's powered over USB.
- **LEDBlinky** is the free program that drives it. It knows each game's controls and colors and lights the panel to match. LaunchBox and Big Box tell it which game is selected, started and closed.
- **Colors need RGB LEDs.** An RGB LED takes **3 outputs** (red, green, blue). One-color LEDs take 1 output and can only be on, off or dimmed.

⚠️ **Count your outputs.** The Tankstick has 22 lit controls (16 player buttons, 1P, 2P, P3, 2 side buttons, the trackball). In full RGB that's 66 outputs, but one LED-Wiz has 32. So one of these is true for your wiring, and the test in 11.2 tells you which:

- Some controls are RGB (3 wires each) and others are one color or not wired.
- Several LEDs share an output, so they always light together.
- There's a second LED-Wiz board.

All three work with LEDBlinky. If you want every control in full color later, a second LED-Wiz adds 32 more outputs (LEDBlinky handles several boards).

## 11.2 Test the LED-Wiz wiring (about 30 minutes)

**Is Windows seeing the board?** Plug the LED-Wiz's USB cable into the OptiPlex. It needs no driver: it shows up as a USB input device. PowerShell:

```powershell
Get-PnpDevice -PresentOnly | Where-Object InstanceId -match 'VID_FAFA'   # the LED-Wiz's USB ID
```

- A line with **Status `OK`** → the board is there. Go on.
- Nothing → try another USB port and cable. Device Manager → **Human Interface Devices** should gain an entry when you plug it in.

**Wiring basics, for reading the results:** the LED-Wiz switches the **minus** side of each LED. The LEDs' **plus** side (the "common anode" leg of an RGB LED) goes to +5 V. So:

- An LED that never lights → it's in backwards, or its +5 V wire is loose.
- An RGB LED that shows the wrong color (say green when you light "red") → its three wires are on the ports in a different order. Don't rewire it: you just write down which port is which color, and LEDBlinky uses that.
- Most arcade LED buttons for 5 V have their resistor built in. Bare LEDs need one, or they burn out.

**Light every port, one at a time.** Install LEDBlinky first (11.3, first step only), then run this. It lights ports 1 to 32 in turn, two seconds each, and says the number:

```powershell
$lb = 'C:\LEDBlinky\LEDBlinky.exe'     # where you installed it
1..32 | ForEach-Object { Write-Host "port $_"; & $lb 14 "$_,48"; Start-Sleep 2; & $lb 14 "$_,0" }
```

(`14 <port>,<level>` is LEDBlinky's "set port" command: level 48 is full brightness, 0 is off.)

Fill in a table like this as it runs, on paper or in Notepad:

| Port | What lit | Color |
|---|---|---|
| 1 | P1 button 1 | red |
| 2 | P1 button 1 | green |
| 3 | P1 button 1 | blue |
| … | … | … |

- [ ] Every wired control lit on at least one port, with no port lighting two places you didn't intend
- [ ] Anything that never lit is on the list to recheck (polarity, loose +5 V, or simply not wired)

That table is your **port map**. The next step types it into LEDBlinky once, and after that you never need it again.

## 11.3 Install and set up LEDBlinky

- [ ] Download LEDBlinky from ledblinky.net and install it to `C:\LEDBlinky`
- [ ] **Input map:** run `GenLEDBlinkyInputMap.exe`. Add your LED-Wiz, and for each port from your table, set:
  - **Port Label:** the control, e.g. `P1 Button 1`. The three ports of one RGB LED get the **same** label.
  - **LED Type:** `Red`, `Green` or `Blue` for RGB ports, `Single` for one-color LEDs.
  - **Control:** the input the button sends. Your buttons act as an Xbox controller, so pick the matching joystick button (P1 button 1 = Joy 1 button A, and so on). They have to match what the emulators see, or the wrong buttons light.
  - The trackball: its own label, e.g. `Trackball`, mapped to the trackball/mouse control.
  - Save.
- [ ] **Config:** run `LEDBlinkyConfig.exe`:
  - **FE** menu → **LaunchBox**.
  - **FE System List Names:** `Main Menu, Main_Menu, Favorites`.
  - **Front End Options** tab → tick **Demo Game Controls**. That lights the selected game's buttons while you're still browsing.
  - **Game Options** tab: turn on button blinking for the start buttons if you like, and pick a pre-game animation.
  - **MAME** tab: point it at the MAME files if you use standalone MAME. For RetroArch's arcade cores, LEDBlinky's own `colors.ini` (it ships with the original panel colors of most arcade games) is what gives arcade games their authentic colors.
  - Save.

## 11.4 Connect LaunchBox and Big Box

- [ ] LaunchBox → **Tools → Options** → find **LEDBlinky** → tick it on → browse to `C:\LEDBlinky` → tick both boxes under the path → OK. Big Box uses the same setting.
- [ ] Test: start Big Box and scroll to an arcade game you know (Street Fighter II, Ms. Pac-Man). The buttons that game uses light in its colors, and the others go dark.

If an arcade game lights nothing, its name in LaunchBox probably doesn't match the MAME name LEDBlinky looks up. Make sure the game's **ROM file name** is the MAME short name (`sf2.zip`), whatever its title says.

## 11.5 Colors for consoles and per platform

Arcade games get their colors from `colors.ini`. Console games run in RetroArch and have no "real" panel colors, so you give each **platform** a default color set once, and every game on it uses that.

- [ ] Run **LEDBlinkyControlsEditor.exe** → add an emulator entry named **exactly** like the LaunchBox platform (e.g. `Nintendo Entertainment System`, `Super Nintendo Entertainment System`, `Sega Genesis`). The names must match LaunchBox's platform names letter for letter.
- [ ] For each platform, set the Player 1 controls and colors, then **copy to Player 2**. Turn on **use main default control mapping** for RetroArch platforms. That fixes most "RetroArch games light nothing" problems.
- [ ] A starting point that matches the real controllers:

| Platform | Colors |
|---|---|
| NES | B and A red, Select and Start white |
| Super Nintendo | Y green, X blue, B yellow, A red, L and R gray/white |
| Genesis / Mega Drive | A, B, C (and X, Y, Z) all blue or white, Start white |
| PlayStation | Square pink, Triangle green, Cross blue, Circle red |
| Nintendo 64 | A blue, B green, C buttons yellow, Start red |
| Neo Geo (arcade) | A red, B yellow, C green, D blue (`colors.ini` has it already) |

- [ ] For a fighter or shmup that needs something special, copy its platform's set to that one game and change it. Copying a similar game (one fighter to the next) saves most of the work.
- [ ] Steam games (Mortal Kombat 1 and 11 from part 4.7): add them by title in the Controls Editor. Titles with a colon sometimes don't match; drop the colon in both places if one lights nothing.

## 11.6 The marquee screen

- [ ] Windows: plug the VGA monitor in (an active HDMI- or DisplayPort-to-VGA adapter on the RTX 3050, which has no VGA port). **Settings → System → Display:** the cabinet screen is **1** and **main display**; the marquee is **2**. Drag screen 2 so it sits **above** screen 1 in the picture, the way it hangs in the cabinet. Set screen 2 to its native resolution (an old VGA monitor: usually 1024×768 or 1280×1024) and **Extend these displays**.
- [ ] Big Box → **Options → General → Marquee Screen** (newer versions may list it under **Views**) → **Screen 2**. Leave the rest on defaults to start.
- [ ] Marquee art: LaunchBox → select all games of a platform → right-click → **Download Metadata and Media** → tick **Arcade - Marquee** (and **Banner** as a fallback for consoles). Big Box falls back on other image types when a game has no marquee.
- [ ] Your old monitor is 4:3 and a marquee is about 3.5:1, so a marquee fills only a band of it. Big Box centers it. If you'd rather fill the top of the screen, Big Box's **Marquee compatibility** option is meant for screens that only show part of their picture. Or edit the marquee images to sit at the top.
- [ ] **Keeping the marquee up while you play:** a game in exclusive full screen can black out the second screen. RetroArch → **Settings → Video → Output → Monitor Index = 1** (the cabinet screen), and **Settings → Video → Fullscreen Mode → Windowed Fullscreen Mode = On**. Then the marquee stays lit through the game. Steam games: pick **Borderless / Windowed fullscreen** in their video settings for the same reason.

## 11.7 Pinball FX: backglass and DMD on the marquee screen

Pinball FX's **cabinet mode** puts the backglass and the dot-matrix display in their own windows, and you place those windows on the marquee monitor.

- [ ] Find the marquee screen's position. Windows puts the main screen's top-left corner at `0,0`. With a 1024×768 marquee sitting above a 1920×1080 main screen and centered over it, its top-left corner is at about **x = 448, y = −768** (negative = above the main screen). Settings → Display shows the arrangement; adjust by eye.
- [ ] Pinball FX → **Options → Cabinet Support** → turn it on. It has three tabs:
  - **General:** turn cabinet mode on.
  - **Backglass Window:** **Window Position** = the marquee's top-left corner (e.g. `448`, `-768`), **Window Size** = its resolution (e.g. `1024`, `768`).
  - **Dotmatrix Window:** place it **inside** the backglass area, along its bottom, e.g. position `448`, `-256` and size `1024`, `256`. The DMD sits over the backglass, where it is on a real machine.
- [ ] Hide the in-game DMD on the playfield screen: **Settings → Gameplay → Dot Matrix Size** → smallest/off. Rotate the playfield if your cabinet screen needs it under **Options → Settings → Video Settings**.
- [ ] Backglass art: PNG files in Pinball FX's `Mods\Cabinet` folder. `PFX.png` is the default for menus and tables without their own, `Table_29.png` is for table 29, and so on. The settings themselves live in `Mods\Cabinet\Settings.ini`, so back that file up once it's right.
- [ ] **Launch tables from Big Box:** add each table as its own game in LaunchBox (platform `Pinball FX`), Application Path = `PinballFX.exe` in the Steam folder, Command-Line Parameters = `-Table <number> -GameMode Classic`. The table numbers are in Zen's Cabinet Mode FAQ (Adventure Land is 29, Judge Dredd is 202). Try one table first: Steam has to be running, and Big Box hands the marquee screen over to the backglass window while the table plays.
- [ ] Optional: LEDBlinky can light the flipper buttons (the 2 side buttons) for the Pinball FX platform the same way as 11.5.

## 11.8 CRT shader and bezel, matched to the buttons

**The shader:** the **Mega Bezel Reflection Shader** (HyperspaceMadness) is the best-looking all-in-one CRT look in RetroArch. It draws the CRT screen with scanlines and curvature, a TV or arcade bezel around it, and the screen's glow reflected onto that bezel.

- [ ] RetroArch → **Settings → Drivers → Video = vulkan** → restart RetroArch. Mega Bezel needs Vulkan or glcore; on D3D it loads very slowly.
- [ ] **Main Menu → Online Updater → Update Slang Shaders**.
- [ ] Load a game → **Quick Menu → Shaders → Load** → `shaders_slang/bezel/Mega_Bezel/Presets/`. Which preset depends on the graphics card:
  - **RTX 3050 (after part 4.7):** `MBZ__1__ADV` presets, the full look with reflections. Back off to `MBZ__3__STD` if a heavy core (N64, PS1 at high internal resolution) stutters.
  - **The old Oland card:** `MBZ__5__POTATO` presets only, or skip the shader until the RTX 3050 is in.
- [ ] Turn on **Quick Menu → Shaders → Save → Simple Presets** before saving your own, so shader updates don't overwrite them.
- [ ] Save it per platform: **Quick Menu → Shaders → Save → Save Core Preset**. Each core (Genesis, SNES, arcade…) gets its own look.

**Matching the bezel to the buttons:** the shader can't read the LED-Wiz, and LEDBlinky can't talk to the shader. So "synced" means you pick the colors to match, once per platform: the lights follow the game live, and the bezel is colored to agree.

- [ ] Quick Menu → **Shaders → Shader Parameters**: find the bezel's **hue**, **saturation** and **brightness** settings (and the separate **frame color**) and tint the bezel to the platform's main button color from 11.5. Neo Geo red, SNES purple-gray, Genesis black with a blue frame, and so on.
- [ ] Save as the **core preset** again. Now every game on that core opens with its bezel in the same family of colors as its lit buttons.
- [ ] Want one game different (a game with its own bezel art)? **Save Game Preset** for just that game, and copy its button colors to it in 11.5 the same way.
- [ ] For more ready-made bezels: the community **Mega Bezel packs** go in a `Mega_Bezel_Packs` folder in the shaders folder, with their own presets.

## Done when

- [ ] The 11.2 port map is filled in, and every wired control lights from the test loop
- [ ] Scrolling in Big Box: Street Fighter II lights its six buttons in the arcade colors, a SNES game lights green, blue, yellow and red, and the unused buttons stay dark
- [ ] The marquee screen shows the selected game's marquee and keeps it up while a RetroArch game plays
- [ ] A Pinball FX table started from Big Box shows its backglass with the DMD on the marquee screen
- [ ] A RetroArch game opens with the CRT bezel, tinted to match its buttons

## Sources

- LED-Wiz board specs (32 outputs, 48 levels, 500 mA, USB powered): [pinballshop.nl product page](https://www.pinballshop.nl/virtual-pinball/game-controllers/led-wiz-32-port-usb-compatible-lighting-and-output-controller-pre-installed-heatsinks/)
- LEDBlinky install, input map, config and the set-port command: [ledblinky.net Install](https://www.ledblinky.net/Install.htm)
- LEDBlinky with LaunchBox (Tools → Options, the FE settings): [Pixelcade's LEDBlinky guide](https://pixelcade.org/ledblinky/), [LaunchBox forum: LEDBlinky custom layouts](https://forums.launchbox-app.com/topic/65485-ledblinky-custom-layouts-tutorial-with-launchbox-bigbox-tips/), [LaunchBox forum: Ultimarc RGB with LaunchBox](https://forums.launchbox-app.com/topic/79899-setting-up-launchboxbigbox-with-ultimarc-rgb-buttonsservostik/)
- Big Box marquee screen: [Game Dummy: digital marquee](https://gamedummy.com/marquee/), [LaunchBox forum: marquee area on a second display](https://forums.launchbox-app.com/topic/92081-how-to-change-the-size-of-the-area-launchboxbigbox-uses-for-marquees-on-second-display/)
- Pinball FX cabinet mode (windows, Settings.ini, backglass files, command line): [Zen's Cabinet Mode FAQ](https://www.pinballfx.com/?page_id=7754)
- Mega Bezel (Vulkan, presets by performance, bezel color parameters): [Mega Bezel README](https://otakon273.duckdns.org/Consoles/RetroArch-Win64/shaders/shaders_slang/bezel/Mega_Bezel/README.md), [libretro: Introducing the Mega Bezel](https://www.libretro.com/index.php/category/mega-bezel/)
