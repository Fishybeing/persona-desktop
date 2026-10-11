# Persona Desktop

A Persona themed Windows desktop: an animated Persona 3 Reload wallpaper with a working calendar, clock and music player, plus a Persona 5 style app menu and system bars.

### [⬇ Download PersonaDesktop.zip](https://github.com/Fishybeing/persona-desktop/releases/latest/download/PersonaDesktop.zip)

Unzip it and double-click **Install.bat**. That's it.

## What you get

**Animated wallpaper** (Persona 3 Reload, the monorail scene)
- Calendar in the top right in the game's style: date, time of day ("After School", "Evening"...), clock, the real moon phase and a countdown to the next full moon.
- The Dark Hour: from midnight to 1 AM the screen turns green, the clock stops and "DARK HOUR" fades in.
- Music player in the bottom right with shuffle, repeat, a volume slider (click, drag or scroll), mute, and a visualizer that follows the song.
- A filter button on the player picks what plays: all music, only Persona, one specific game, or everything else. Shuffle and skip stay inside your pick.
- Every song gets its BPM worked out the first time it plays, and the player pulses on the beat.
- Under each song it shows which game it's from (Persona 5, Persona 3 Reload, UNDERTALE...).

**Persona 5 menu** (top left)
- Click the red MENU tab to open or close it. It uses the Persona 5 menu font and sounds.
- It lists everything installed on your PC (Start menu apps, Steam games, launchers), sorted into Games, Social, Internet, Media, Create, Office and Tools, and opens them with one click. Uninstallers, help files and Windows admin tools are left out.
- Hit UPDATE LIST after installing or removing something.

**Persona 5 system bars** (bottom left)
- CPU and RAM use as Persona 5 health bars.

## Requirements

- Windows 10 or 11
- winget (already on most PCs; if not, install "App Installer" from the Microsoft Store)

The installer sets up [Lively Wallpaper](https://github.com/rocksdanister/lively) and [Rainmeter](https://www.rainmeter.net/) through winget, which checks each installer before it runs. Windows will ask once for permission to install Rainmeter.

## Adding your music

The player doesn't come with music. Put your own files (mp3, m4a, ogg, opus, flac, wav or webm) in the music folder, then run **Update playlist**. Both are in the Start menu under **Persona Desktop**.

If you have [yt-dlp](https://github.com/yt-dlp/yt-dlp) installed and your files came from YouTube (the file name ends with the video ID in brackets), Update playlist also looks up which game each song is from.

## Optional: Persona 5 icons

For Persona 5 style icons in the menu and on the Recycle Bin and This PC, download [FrozenVayne's Persona 5 Desktop Icon Pack](https://www.deviantart.com/frozenvayne/art/Persona-5-Desktop-Icon-Pack-Version-1-0-747871613) (needs a free DeviantArt account), leave the zip in your Downloads folder and run Install.bat again.

## Settings

- **Wallpaper:** open Lively, right-click the wallpaper and choose Customize. You can switch the animation off (uses almost no CPU then), change the clock to 12 hour, hide parts, and change when the Dark Hour happens.
- **Saving power:** if your mouse hasn't been on the desktop for 5 minutes, the wallpaper fades to the still picture and stops the video. Move the mouse over the desktop and it comes back. The music keeps playing. You can change the 5 minutes (or turn it off) in Customize.
- **Menu and bars:** drag them anywhere. Right-click for Rainmeter's options.
- **Only Persona games:** to hide games that don't have a Persona 5 icon, create `menu-settings.json` in `%LOCALAPPDATA%\PersonaDesktop\menu` with `{ "personaIconsOnlyInGames": true, "alwaysShowGames": ["Farming Simulator"] }` (list any games you want to keep anyway), then click UPDATE LIST. Add `"hideSections": ["TOOLS"]` to the same file to hide whole sections.

## Antivirus

The installer is a plain PowerShell script that isn't code-signed, so some antivirus programs get nervous about it. Everything it does is in [`setup/install.ps1`](setup/install.ps1) if you want to read it first.

## Uninstalling

Start menu > Persona Desktop > **Uninstall Persona Desktop**. Your music gets moved to `Music\Persona Desktop music` first, and your old icons come back. Lively and Rainmeter stay installed; the uninstaller tells you how to remove them too.

## Credits

See [CREDITS.md](CREDITS.md). Persona is a series by ATLUS and SEGA. This is a free fan project and isn't affiliated with them.
