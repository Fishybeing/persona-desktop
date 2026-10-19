#!/usr/bin/env python3
"""Linux version of 'Update playlist.ps1': scans the music folder and writes music/playlist.js for the wallpaper."""
import json, os, re, shutil, subprocess, sys, tempfile, urllib.parse

APP = os.path.dirname(os.path.abspath(__file__))
WALL = os.path.join(os.path.dirname(APP), "wallpaper")
if len(sys.argv) > 1:
    WALL = sys.argv[1]
MUSIC = os.path.join(WALL, "music")
META = os.path.join(MUSIC, "meta.json")
EXTS = {".mp3", ".m4a", ".aac", ".ogg", ".opus", ".flac", ".wav", ".webm"}
YT_ID = re.compile(r"\[([A-Za-z0-9_-]{11})\]$")

GAMES = [
    (r"persona\s*5.*royal|p5r", "PERSONA 5 ROYAL"),
    (r"persona\s*5|persona5|p5 ", "PERSONA 5"),
    (r"persona\s*3.*reload|p3r", "PERSONA 3 RELOAD"),
    (r"persona\s*3|persona3", "PERSONA 3"),
    (r"persona\s*4|persona4", "PERSONA 4"),
    (r"undertale", "UNDERTALE"),
    (r"deltarune", "DELTARUNE"),
    (r"ultrakill|cyber grind", "ULTRAKILL"),
    (r"metal gear rising", "METAL GEAR RISING"),
    (r"metal gear", "METAL GEAR"),
    (r"castlevania", "CASTLEVANIA"),
    (r"kingdom come", "KINGDOM COME: DELIVERANCE"),
]


def get_game(text):
    for rx, name in GAMES:
        if re.search(rx, text, re.I):
            return name
    return ""


def clean_album(a):
    if not a or a == "NA":
        return ""
    a = re.sub(r"\s*[\(\[]?(original\s+)?(game\s+)?(sound\s*track|ost|soundtrack)[\)\]]?.*$", "", a, flags=re.I)
    a = re.sub(r"\s*[\(\[][^\)\]]*$", "", a)
    return a.strip(" -:")


def main():
    os.makedirs(MUSIC, exist_ok=True)
    files = []
    for d, _, names in os.walk(MUSIC, followlinks=True):
        for n in names:
            if os.path.splitext(n)[1].lower() in EXTS:
                files.append(os.path.join(d, n))

    try:
        with open(META, encoding="utf-8-sig") as f:
            meta = json.load(f)
    except (OSError, ValueError):
        meta = {}
    base = lambda p: os.path.splitext(os.path.basename(p))[0]
    missing = sorted({m.group(1) for p in files for m in [YT_ID.search(base(p))] if m and m.group(1) not in meta})
    yt = shutil.which("yt-dlp") or (os.path.expanduser("~/.local/bin/yt-dlp") if os.path.exists(os.path.expanduser("~/.local/bin/yt-dlp")) else None)
    if missing and yt:
        print("Looking up %d songs on YouTube Music..." % len(missing))
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as t:
            t.write("\n".join("https://music.youtube.com/watch?v=" + i for i in missing))
        out = subprocess.run([yt, "--skip-download", "--no-warnings", "--ignore-errors", "--encoding", "utf-8", "-a", t.name,
                              "--print", "%(id)s\t%(album)s\t%(artist)s\t%(title)s"], capture_output=True, text=True, encoding="utf-8").stdout
        os.unlink(t.name)
        for line in out.splitlines():
            p = line.split("\t")
            if len(p) >= 4:
                meta[p[0]] = {"album": p[1], "artist": p[2], "title": p[3]}
        for i in missing:
            meta.setdefault(i, {"album": "NA", "artist": "NA", "title": "NA"})
        with open(META, "w", encoding="utf-8") as f:
            json.dump(dict(sorted(meta.items())), f, indent=2, ensure_ascii=False)

    music_real = os.path.realpath(MUSIC)
    out = []
    for path in sorted(files, key=lambda p: (os.path.basename(os.path.dirname(p)) != "Persona 3 Reload", p.lower())):
        b, folder = base(path), os.path.dirname(path)
        folder_name = os.path.basename(folder)
        in_root = os.path.realpath(folder) == music_real
        m = YT_ID.search(b)
        info = meta.get(m.group(1)) if m else None
        title = re.sub(r"^\s*\d+[\s\.\-_]+", "", re.sub(r"\s*\[[A-Za-z0-9_-]{11}\]$", "", b)).strip()
        title = re.sub(r"\s*\([^)]*(soundtrack|ost)[^)]*\)\s*$", "", re.sub(r"\s*\([^)]*(soundtrack|ost)[^)]*\)\s*-\s*.*$", "", title, flags=re.I), flags=re.I).strip()
        album = str(info.get("album") or "") if info else ""
        artist = ""
        if info and info.get("artist") and info["artist"] != "NA":
            artist = next((a for a in re.split(r",\s*", str(info["artist"])) if not re.match(r"^ATLUS", a, re.I)), "")
        game = get_game(album + " " + b + " " + folder_name) or clean_album(album)
        folder_cat = False
        exclusive = os.path.exists(os.path.join(folder, "only-when-selected.txt"))
        if not in_root and folder_name not in ("Other Music", "Persona 3 Reload"):
            game, folder_cat = folder_name.upper(), True
        if game and game == title:
            game = ""
        if not artist and not in_root:
            artist = folder_name
        rel = os.path.relpath(path, WALL).split(os.sep)
        out.append({"file": "/".join(urllib.parse.quote(x, safe="") for x in rel), "title": title, "artist": artist,
                    "game": game, "folder": folder_cat, "exclusive": exclusive})

    with open(os.path.join(MUSIC, "playlist.js"), "w", encoding="utf-8") as f:
        f.write("window.P3_PLAYLIST = " + json.dumps(out, indent=2, ensure_ascii=False) + ";\n")
    print("Playlist updated: %d %s." % (len(out), "song" if len(out) == 1 else "songs"))


if __name__ == "__main__":
    main()
