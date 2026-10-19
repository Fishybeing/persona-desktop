#!/usr/bin/env python3
"""Cuts the recorded clips into the 'now on Linux' video, with Persona style titles, wipes and an end card.

  python assemble.py                  uses clips/windows-*.mp4 and clips/linux-*.mp4, writes persona-desktop-linux.mp4
  python assemble.py --preview        no Windows clips yet: Linux footage stands in for them (marked on screen)
  python assemble.py --music FILE     the song under the whole video (default: Full Moon Full Life from the music folder)

Needs ffmpeg on PATH and Pillow (pip install pillow).
"""
import argparse, glob, json, math, os, random, shutil, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
W, H, FPS, OFPS = 1920, 1080, 60, 30  # video size, video fps, overlay (titles) fps
FONT_P5 = os.path.join(REPO, "menu", "PersonaMenu", "@Resources", "Fonts", "PersonifiedUXRegular.ttf")
FONT_P3 = os.path.join(REPO, "wallpaper", "fonts", "BarlowCondensed-ExtraBoldItalic.ttf")
RED, BLACK, WHITE = (229, 25, 28), (10, 10, 10), (255, 255, 255)


def font(path, size):
    return ImageFont.truetype(path, size)


def ease_out(t):
    t = max(0.0, min(1.0, t))
    return 1 - (1 - t) ** 3


# ---------- title graphics, drawn per overlay frame ----------

def ransom(img, text, cx, cy, t, dur, seed=5, size=150):
    """Persona 5 style cut-out letters that pop in one by one, over a black band."""
    rnd = random.Random(seed)
    d = ImageDraw.Draw(img)
    band_in, band_out = ease_out(t / 0.18), ease_out((t - (dur - 0.25)) / 0.25)
    if t > dur:
        return
    # the band slides in from the left and out to the right
    off = -W * (1 - band_in) + W * band_out
    bh = int(size * 1.55)
    d.polygon([(off - 60, cy - bh // 2 + 18), (off + W + 60, cy - bh // 2 - 18), (off + W + 60, cy + bh // 2 - 18), (off - 60, cy + bh // 2 + 18)], fill=RED)
    d.polygon([(off - 60, cy - bh // 2 + 32), (off + W + 60, cy - bh // 2 - 4), (off + W + 60, cy + bh // 2 - 32), (off - 60, cy + bh // 2 + 4)], fill=BLACK)
    if band_out > 0:
        return
    letters = []
    for i, ch in enumerate(text):
        if ch == " ":
            letters.append(None)
            continue
        style = rnd.choice(["wb", "bw", "wb", "rw"])
        fs = int(size * rnd.uniform(0.82, 1.08))
        f = font(FONT_P5 if rnd.random() < 0.6 else FONT_P3, fs)
        bg, fg = {"wb": (WHITE, BLACK), "bw": (BLACK, WHITE), "rw": (RED, WHITE)}[style]
        box = f.getbbox(ch)
        tw, th = box[2] - box[0], box[3] - box[1]
        pad = int(fs * 0.12)
        tile = Image.new("RGBA", (tw + 2 * pad, th + 2 * pad), bg + (255,))
        ImageDraw.Draw(tile).text((pad - box[0], pad - box[1]), ch, font=f, fill=fg)
        tile = tile.rotate(rnd.uniform(-9, 9), resample=Image.BICUBIC, expand=True)
        letters.append((tile, rnd.uniform(-14, 14), i))
    gap = int(size * 0.32)
    total = sum(l[0].width if l else gap for l in letters) - 8 * (len(letters) - 1)
    x = cx - total // 2
    for l in letters:
        if l is None:
            x += gap
            continue
        tile, dy, i = l
        appear = 0.16 + i * 0.045
        if t >= appear:
            k = ease_out((t - appear) / 0.09)
            sc = 1.6 - 0.6 * k
            tt = tile.resize((max(1, int(tile.width * sc)), max(1, int(tile.height * sc))), Image.BICUBIC)
            shake = 3 * math.sin(t * 40 + i) if t < appear + 0.15 else 0
            img.alpha_composite(tt, (int(x + tile.width / 2 - tt.width / 2), int(cy + dy - tt.height / 2 + shake)))
        x += tile.width - 8


def caption(img, text, t, dur, x=150, y=860, size=64):
    """Red slanted tag that slides in from the left."""
    if t < 0 or t > dur:
        return
    k_in, k_out = ease_out(t / 0.22), ease_out((t - (dur - 0.22)) / 0.22)
    f = font(FONT_P5, size)
    box = f.getbbox(text)
    tw, th = box[2] - box[0], box[3] - box[1]
    pad_x, pad_y, sk = 34, 18, 22
    wdt, hgt = tw + 2 * pad_x, th + 2 * pad_y
    ox = int(x - (wdt + x + 80) * (1 - k_in) - (wdt + x + 80) * k_out)
    d = ImageDraw.Draw(img)
    d.polygon([(ox + sk + 10, y + 10), (ox + wdt + sk + 10, y + 10), (ox + wdt + 10, y + hgt + 10), (ox + 10, y + hgt + 10)], fill=(0, 0, 0, 200))
    d.polygon([(ox + sk, y), (ox + wdt + sk, y), (ox + wdt, y + hgt), (ox, y + hgt)], fill=RED)
    d.text((ox + pad_x + sk // 2 - box[0], y + pad_y - box[1]), text, font=f, fill=WHITE)


def wipe(img, t, dur=0.5):
    """Red and black slashes that sweep across and cover the screen at the halfway point (where the cut is)."""
    if t < 0 or t > dur:
        return
    p = t / dur
    d = ImageDraw.Draw(img)
    slant = 500
    for color, lag in ((RED, 0.0), (BLACK, 0.12)):
        q = max(0.0, min(1.0, (p - lag) / (1 - 0.12)))
        lead = -slant + (W + 2 * slant) * ease_out(min(1, q * 2))       # front edge
        tail = -slant + (W + 2 * slant) * ease_out(max(0, q * 2 - 1))   # back edge
        if lead > tail:
            d.polygon([(tail, 0), (lead + slant, 0), (lead, H), (tail - slant, H)], fill=color)


def end_card(img, t):
    d = ImageDraw.Draw(img)
    k = ease_out(t / 0.3)
    # labels on each half
    f = font(FONT_P5, 70)
    for text, x, y in (("WINDOWS", 140, 140), ("LINUX", 1240, 900)):
        box = f.getbbox(text)
        tw = box[2] - box[0]
        xx = x if text == "WINDOWS" else x - tw
        xx += int((-1 if text == "WINDOWS" else 1) * 600 * (1 - k))
        d.polygon([(xx - 30, y - 12), (xx + tw + 40, y - 18), (xx + tw + 26, y + 92), (xx - 44, y + 98)], fill=BLACK)
        d.text((xx - box[0], y - box[1] + 6), text, font=f, fill=WHITE)
    if t > 0.35:
        ransom(img, "PERSONA DESKTOP", W // 2, H // 2 - 10, t - 0.35, 99, seed=11, size=118)
    if t > 1.2:
        f2 = font(FONT_P3, 46)
        s = "github.com/Fishybeing/persona-desktop"
        box = f2.getbbox(s)
        a = int(255 * ease_out((t - 1.2) / 0.4))
        layer = Image.new("RGBA", img.size)
        ImageDraw.Draw(layer).text((W // 2 - (box[2] - box[0]) // 2, H // 2 + 130), s, font=f2, fill=(255, 255, 255, a))
        img.alpha_composite(layer)


def diagonal_mask(path):
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).polygon([(W * 0.62, 0), (W, 0), (W, H), (W * 0.38, H)], fill=255)
    m.save(path)


# ---------- timeline ----------

def load_clip(clips, os_, shot):
    path = os.path.join(clips, "%s-%s.mp4" % (os_, shot))
    meta = os.path.join(clips, "%s-%s.json" % (os_, shot))
    if not os.path.exists(path):
        return None
    with open(meta, encoding="utf-8") as f:
        m = json.load(f)
    m["path"] = path
    return m


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--clips", default=os.path.join(HERE, "clips"))
    ap.add_argument("--out", default=os.path.join(HERE, "persona-desktop-linux.mp4"))
    ap.add_argument("--preview", action="store_true", help="use Linux footage where the Windows clips would go")
    ap.add_argument("--music", help="song under the video")
    ap.add_argument("--music-start", type=float, default=0.0, help="where in the song to start (seconds)")
    ap.add_argument("--keep", action="store_true", help="keep the work folder")
    a = ap.parse_args()

    lin = {s: load_clip(a.clips, "linux", s) for s in ("open", "player", "darkhour", "close")}
    win = {s: load_clip(a.clips, "windows", s) for s in ("open", "close")}
    if not all(lin.values()):
        sys.exit("Missing Linux clips in %s (need linux-open, -player, -darkhour, -close)." % a.clips)
    stand_in = not all(win.values())
    if stand_in and not a.preview:
        sys.exit("No Windows clips yet (windows-open.mp4 and windows-close.mp4). Record them on Windows, or use --preview.")
    if stand_in:
        win = {"open": lin["open"], "close": lin["close"]}

    def ev(c, name):
        return c["events"][name]

    # (clip, start, end, takes the clip's sound, titles to draw: [(kind, args)])
    segs = []
    wo, lo = ev(win["open"], "OPEN"), ev(lin["open"], "OPEN")
    segs.append(dict(clip=win["open"], a=wo - 3.2, b=wo + 0.04, sound=False, tag="win"))
    segs.append(dict(clip=lin["open"], a=lo + 0.12, b=lo + 3.4, sound=True, titles=[("ransom", "NOW ON LINUX", 0.15, 2.9)], wipe_out=True))
    p = lin["player"]
    segs.append(dict(clip=p, a=ev(p, "PLAY") - 1.3, b=ev(p, "AWAY") + 0.8, sound=False, titles=[("caption", "SAME MUSIC PLAYER", 0.35, 3.6), ("caption", "YOUR PLAYLISTS TOO", 4.2, 2.6)], wipe_out=True))
    dk = lin["darkhour"]
    segs.append(dict(clip=dk, a=ev(dk, "DARK") - 0.4, b=ev(dk, "DARK") + 6.2, sound=False, titles=[("caption", "THE DARK HOUR, TOO", 0.5, 3.0)], wipe_out=True))
    lc, wc = ev(lin["close"], "CLOSE"), ev(win["close"], "CLOSE")
    segs.append(dict(clip=lin["close"], a=lc - 2.3, b=lc + 0.04, sound=True, titles=[("caption", "YOUR LINUX APPS", 0.2, 1.9)]))
    segs.append(dict(clip=win["close"], a=wc + 0.12, b=wc + 2.9, sound=False, tag="win", titles=[("caption", "...AND BACK TO WINDOWS", 0.35, 2.2)]))
    END = 5.0
    end_win, end_lin = (win["close"], wc + 3.0), (lin["close"], lc + 3.0)

    t = 0.0
    for s in segs:
        s["t"] = t
        t += s["b"] - s["a"]
    total = t + END
    print("Video length: %.1fs" % total)

    work = tempfile.mkdtemp(prefix="pd-video-")
    try:
        # ----- titles overlay, one PNG per overlay frame -----
        ov = os.path.join(work, "ov")
        os.makedirs(ov)
        blank = os.path.join(ov, "blank.png")
        Image.new("RGBA", (W, H)).save(blank)
        n = int(math.ceil(total * OFPS))
        events = []
        for i, s in enumerate(segs):
            for kind, text, at, dur in s.get("titles", []):
                events.append((kind, text, s["t"] + at, dur))
            if s.get("wipe_out"):
                events.append(("wipe", None, s["t"] + (s["b"] - s["a"]) - 0.25, 0.5))
            if stand_in and s.get("tag") == "win":
                events.append(("note", None, s["t"], s["b"] - s["a"]))
        events.append(("wipe", None, total - END - 0.25, 0.5))
        events.append(("end", None, total - END, END))
        if stand_in:
            events.append(("note", None, total - END, END))
        print("Drawing %d title frames..." % n)
        for fi in range(n):
            tt = fi / OFPS
            active = [e for e in events if e[2] - 0.01 <= tt <= e[2] + e[3]]
            out = os.path.join(ov, "%05d.png" % fi)
            if not active:
                os.link(blank, out) if hasattr(os, "link") else shutil.copy(blank, out)
                continue
            img = Image.new("RGBA", (W, H))
            for kind, text, at, dur in active:
                lt = tt - at
                if kind == "ransom":
                    ransom(img, text, W // 2, H // 2 - 40, lt, dur)
                elif kind == "caption":
                    caption(img, text, lt, dur)
                elif kind == "wipe":
                    wipe(img, lt, dur)
                elif kind == "end":
                    end_card(img, lt)
                elif kind == "note":
                    d = ImageDraw.Draw(img)
                    d.rectangle([W // 2 - 380, 40, W // 2 + 380, 110], fill=(0, 0, 0, 170))
                    d.text((W // 2 - 360, 52), "PREVIEW: WINDOWS FOOTAGE GOES HERE", font=font(FONT_P3, 44), fill=(255, 220, 0, 255))
            img.save(out, compress_level=1)
        mask = os.path.join(work, "mask.png")
        diagonal_mask(mask)

        # ----- cut the footage -----
        inputs, fc, vlabels, alabels = [], [], [], []
        def inp(path):
            if path not in inputs:
                inputs.append(path)
            return inputs.index(path)
        for i, s in enumerate(segs):
            k = inp(s["clip"]["path"])
            fc.append("[%d:v]trim=%.4f:%.4f,setpts=PTS-STARTPTS,fps=%d,scale=%d:%d,setsar=1[v%d]" % (k, s["a"], s["b"], FPS, W, H, i))
            vlabels.append("[v%d]" % i)
        kw, kl = inp(end_win[0]["path"]), inp(end_lin[0]["path"])
        nm = len(inputs)
        fc.append("[%d:v]trim=%.4f:%.4f,setpts=PTS-STARTPTS,fps=%d,scale=%d:%d,setsar=1[ew]" % (kw, end_win[1], end_win[1] + END, FPS, W, H))
        fc.append("[%d:v]trim=%.4f:%.4f,setpts=PTS-STARTPTS,fps=%d,scale=%d:%d,setsar=1,format=rgba[el]" % (kl, end_lin[1], end_lin[1] + END, FPS, W, H))
        fc.append("[%d:v]format=gray,scale=%d:%d[mk]" % (nm, W, H))
        fc.append("[el][mk]alphamerge[elm]")
        fc.append("[ew][elm]overlay=0:0:shortest=1,format=yuv420p[vend]")
        vlabels.append("[vend]")
        fc.append("%sconcat=n=%d:v=1:a=0[base]" % ("".join(vlabels), len(vlabels)))
        fc.append("[%d:v]fps=%d[ovf]" % (nm + 1, FPS))
        fc.append("[base][ovf]overlay=0:0:shortest=1:format=auto,format=yuv420p[vout]")
        # sound: the song underneath, plus the menu sounds from the Linux clips
        music = a.music or next(iter(sorted(glob.glob(os.path.expanduser("~/.local/share/persona-desktop/wallpaper/music/Full Moon Full Life*")))), None)
        mi = None
        args_in = []
        for pth in inputs:
            args_in += ["-i", pth]
        args_in += ["-loop", "1", "-i", mask, "-framerate", str(OFPS), "-i", os.path.join(ov, "%05d.png")]
        nxt = nm + 2
        mixes = []
        if music and os.path.exists(music):
            args_in += ["-ss", str(a.music_start), "-i", music]
            mi = nxt
            nxt += 1
            fc.append("[%d:a]atrim=0:%.3f,asetpts=PTS-STARTPTS,volume=0.6,afade=t=in:d=0.6,afade=t=out:st=%.3f:d=1.8[mus]" % (mi, total, total - 1.8))
            mixes.append("[mus]")
        else:
            print("No song found, the video has only the menu sounds. Use --music FILE.")
        for i, s in enumerate(segs):
            if s.get("sound") and not (stand_in and s.get("tag") == "win"):
                k = inputs.index(s["clip"]["path"])
                ms = int(s["t"] * 1000)
                fc.append("[%d:a]atrim=%.4f:%.4f,asetpts=PTS-STARTPTS,volume=1.4,adelay=%d|%d[s%d]" % (k, s["a"], s["b"], ms, ms, i))
                mixes.append("[s%d]" % i)
        if mixes:
            fc.append("%samix=inputs=%d:normalize=0:duration=longest,atrim=0:%.3f[aout]" % ("".join(mixes), len(mixes), total))
        cmd = ["ffmpeg", "-hide_banner", "-y"] + args_in + ["-filter_complex", ";".join(fc), "-map", "[vout]"]
        if mixes:
            cmd += ["-map", "[aout]", "-c:a", "aac", "-b:a", "192k"]
        cmd += ["-c:v", "libx264", "-preset", "medium", "-crf", "18", "-r", str(FPS), "-movflags", "+faststart", "-t", "%.3f" % total, a.out]
        print("Rendering %s ..." % a.out)
        r = subprocess.run(cmd, stderr=subprocess.PIPE, text=True, encoding="utf-8", errors="replace")
        if r.returncode:
            print(r.stderr[-4000:])
            sys.exit("ffmpeg failed.")
        print("Done: %s" % a.out)
    finally:
        if a.keep:
            print("Work folder: " + work)
        else:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
