# Recording the Windows half of the "now on Linux" video

You're helping make a short video for Persona Desktop (this repo). The Linux half is already recorded. Your job is to
record the matching Windows shots on this PC and then cut the finished video with the titles and animations.

The idea of the video: it starts on the Windows desktop, the cursor clicks the red MENU tab, and at the exact moment the
menu opens it cuts to Linux, so it looks like the same desktop turned into Linux. After a few Linux shots (music
player, Dark Hour, the menu with Linux apps), the cursor closes the menu and it cuts back to Windows the same way.
It ends on a split screen, Windows on the left and Linux on the right.

For the cuts to be invisible, everything on screen has to match the Linux recording: same mouse path, same clock, same
song in the player, and the wallpaper video on the same frame. The scripts take care of that. Your part is to get the
PC into the right state and run them.

**Rules from the user:** commits are authored by the user only. Never add co-author trailers or "generated with" lines
to commits, pull requests or files. Don't push to GitHub unless the user asks.

## What's in `video/`

| File | What it does |
|---|---|
| `shots.json` | The shots: mouse path, timings, clock time/date, song. Shared by both systems, don't change the `open`/`close` shots or the cut won't match. |
| `record.py` | Records the shots for whichever system it runs on (`windows-open.mp4`, `windows-close.mp4` here). Moves the mouse itself. |
| `assemble.py` | Cuts the clips together and draws the Persona-style titles, slash wipes and the end card. |
| `clips/` | Recorded clips + a `.json` per clip with the exact click times. The Linux clips go here too. |

## 1. Get this branch and the Linux clips

1. Check out the `linux` branch of https://github.com/Fishybeing/persona-desktop (the user's repo).
2. The Linux clips (`linux-open`, `linux-player`, `linux-darkhour`, `linux-close`, each `.mp4` + `.json`) come from
   the user's Linux PC. Ask the user where they put them and copy all eight files into `video\clips\`.

## 2. Update the wallpaper on this PC

The `linux` branch changed the shared wallpaper (`wallpaper\index.html`, `wallpaper\hud.js`): it adds a recording
mode, which reads an optional `record.js` next to `index.html`. The installed copy on this PC doesn't have that yet.

- Run `Install.bat` from this branch's checkout (it updates the files and keeps the user's music), **or**
  copy `wallpaper\index.html` and `wallpaper\hud.js` into the Lively wallpaper folder, normally
  `%LOCALAPPDATA%\Lively Wallpaper\Library\wallpapers\persona-monorail`. If Lively was installed from the Microsoft
  Store the folder is elsewhere. `music-app\PersonaMusic.ps1` has the code that finds it.

## 3. Put the same song in the player

The player is on screen at the cut, so it has to show the same song as on Linux: **"Full Moon Full Life"** (Persona 3
Reload, Azumi Takahashi), YouTube Music id `hWhgrA2dhrk`.

```powershell
winget install yt-dlp.yt-dlp
cd "<the wallpaper folder>\music"
yt-dlp -x --audio-format mp3 --audio-quality 0 -o "Full Moon Full Life [%(id)s].%(ext)s" "https://music.youtube.com/watch?v=hWhgrA2dhrk"
```

Then run **Start > Persona Desktop > Update playlist**. Recording mode picks that song by name, so the player shows
it whatever else is in the playlist.

## 4. Get the PC ready

- **Display:** 1920x1080 at **100% scaling** (Settings > System > Display). `record.py` refuses to run otherwise,
  because the menu and buttons are at fixed pixel positions. Change it back afterwards if the user wants.
- **Python and ffmpeg:** `winget install Python.Python.3.12 Gyan.FFmpeg`, then open a new terminal and run
  `pip install pillow`. Check that `ffmpeg -version` works.
- **Lively Customize:** leave the defaults on (animated background, calendar, player, 24-hour clock). Dark Hour on
  "Midnight to 1 AM".
- **Rainmeter:** the PersonaMenu and Persona 5 System skins should be loaded. `record.py` moves the menu to (110, 36)
  and closes or opens it with Rainmeter bangs, so you don't need to place it by hand.
- **Internet on:** `record.py` checks the clock against an NTP server. Windows clocks are often off by a second or
  more; the script measures that and corrects for it.
- Close notifications/popups if you can (Focus assist on). Anything that pops up will be in the shot.

## 5. Record

Tell the user the mouse will move by itself for about a minute and not to touch it. Then:

```powershell
cd video
python record.py
```

It runs only the shots meant for Windows (`open` and `close`). For each one it writes `record.js` into the wallpaper
folder, reloads the wallpaper with `Lively.exe setwp`, shows the desktop (Win+D), waits until the wallpaper video
reaches the agreed frame, and then plays the mouse path. Afterwards it deletes `record.js` and reloads the wallpaper.

### Check the clips

Pull out frames and look at them:

```powershell
ffmpeg -ss <OPEN-0.2> -i clips\windows-open.mp4 -frames:v 1 before.png
ffmpeg -ss <OPEN+0.3> -i clips\windows-open.mp4 -frames:v 1 after.png
```

(`OPEN` is in `clips\windows-open.json` under `events`.) Check that:

1. The calendar says **10/26 MON, EVENING, 18:30, FULL MOON TONIGHT**. If it shows the real date/time, the wallpaper
   didn't load `record.js`. Make sure `index.html` has `<script src="record.js"></script>` and reload Lively again.
2. The player shows **Full Moon Full Life** and is paused at 0:00.
3. The menu is closed before OPEN and open after. The cursor is on the red MENU tab in both.
4. The wallpaper picture matches `linux-open.mp4` at its own OPEN time (same train/sky position). Put the two frames
   side by side. A small difference is fine; if it's clearly a different moment (more than half a second), the clocks
   didn't line up. Run it again; if it keeps happening, look at the "clock is off by" line it printed.
5. Same for `windows-close.mp4` at CLOSE against `linux-close.mp4`: menu open before, closed after.

If `Lively.exe setwp` doesn't reload the page (calendar still shows the real time), try `Lively.exe closewp` and
then `setwp`, or restart Lively before each shot, and fix that in `Windows.reload()` in `record.py`.

## 6. Make the video

```powershell
python assemble.py --music "<the wallpaper folder>\music\Full Moon Full Life [hWhgrA2dhrk].mp3"
```

It writes `video\persona-desktop-linux.mp4` (about 32 seconds, 1080p60). It takes a few minutes. Then look through it,
especially the two cuts (around 3 s and 25 s), and show it to the user.

The titles and animations are all in `assemble.py`:

- `ransom()`: the Persona 5 cut-out letters ("NOW ON LINUX", "PERSONA DESKTOP").
- `caption()`: the red slanted captions ("SAME MUSIC PLAYER", ...).
- `wipe()`: the red and black slash transitions between Linux shots.
- `end_card()`: the split-screen ending with the GitHub link.
- The list of segments with their caption text and timing is in `main()` (`segs.append(...)`).

Change the wording or timing there if the user asks. Keep the cut points (`OPEN`/`CLOSE` offsets) as they are.

To check the edit without Windows clips, `python assemble.py --preview` uses Linux footage in their place.

## Notes

- The song is copyrighted (ATLUS). Uploading the video publicly may get a content claim; that's the user's call.
- The Windows desktop has the taskbar at the bottom and Linux has a panel at the top. That difference is the point of
  the cut, don't try to hide it.
- Any problem with the wallpaper itself: `Start > Persona Desktop > Get log` makes a zip with diagnostics.
