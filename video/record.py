#!/usr/bin/env python3
"""Records the shots for the 'now on Linux' video. The same script runs on Windows and on Linux, so the mouse
moves exactly the same way on both and the clips can be cut together seamlessly.

  python record.py                 record every shot for this system into ./clips
  python record.py --only open     just one shot
  python record.py --list          show the shots

Needs ffmpeg on PATH (and xdotool on Linux). Don't touch the mouse while it records.
"""
import argparse, ctypes, json, os, platform, re, shutil, socket, struct, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
WIN = platform.system() == "Windows"
OS = "windows" if WIN else "linux"


# ---------- clock: both systems agree on the time through NTP, so the wallpaper video is on the same frame ----------

def ntp_offset(server="pool.ntp.org", tries=4):
    """Seconds to add to this computer's clock to get the real time."""
    best = None
    for _ in range(tries):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.settimeout(2)
            t0 = time.time()
            s.sendto(b"\x1b" + 47 * b"\0", (server, 123))
            data = s.recv(48)
            t3 = time.time()
            s.close()
            sec, frac = struct.unpack("!II", data[40:48])
            t2 = sec - 2208988800 + frac / 2 ** 32
            sec, frac = struct.unpack("!II", data[32:40])
            t1 = sec - 2208988800 + frac / 2 ** 32
            delay, off = (t3 - t0) - (t2 - t1), ((t1 - t0) + (t2 - t3)) / 2
            if best is None or delay < best[0]:
                best = (delay, off)
        except OSError:
            pass
    if best is None:
        print("  ! Couldn't reach an NTP server, using this computer's clock as it is.")
        return 0.0
    return best[1]


def sleep_until(t):
    while True:
        left = t - time.time()
        if left <= 0:
            return
        time.sleep(min(left, 0.5) if left > 0.02 else 0.001)


# ---------- mouse ----------

if WIN:
    from ctypes import wintypes
    user32 = ctypes.windll.user32
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)
    except Exception:
        user32.SetProcessDPIAware()

    def mouse_to(x, y):
        user32.SetCursorPos(int(round(x)), int(round(y)))

    def mouse_pos():
        p = wintypes.POINT()
        user32.GetCursorPos(ctypes.byref(p))
        return p.x, p.y

    def click():
        user32.mouse_event(0x0002, 0, 0, 0, 0)
        time.sleep(0.05)
        user32.mouse_event(0x0004, 0, 0, 0, 0)

    def screen_size():
        return user32.GetSystemMetrics(0), user32.GetSystemMetrics(1)
else:
    def mouse_to(x, y):
        subprocess.run(["xdotool", "mousemove", str(int(round(x))), str(int(round(y)))])

    def mouse_pos():
        out = subprocess.run(["xdotool", "getmouselocation", "--shell"], capture_output=True, text=True).stdout
        v = dict(l.split("=") for l in out.split() if "=" in l)
        return int(v["X"]), int(v["Y"])

    def click():
        subprocess.run(["xdotool", "click", "1"])

    def screen_size():
        out = subprocess.run(["xdotool", "getdisplaygeometry"], capture_output=True, text=True).stdout.split()
        return int(out[0]), int(out[1])


def ease(t):
    return 4 * t ** 3 if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2


def glide(x1, y1, seconds, start):
    """Moves the mouse in a smooth curve, keeping to the timeline that started at `start`."""
    x0, y0 = mouse_pos()
    end = start + seconds
    while True:
        now = time.time()
        if now >= end:
            break
        k = ease((now - start) / seconds)
        mouse_to(x0 + (x1 - x0) * k, y0 + (y1 - y0) * k)
        time.sleep(1 / 120)
    mouse_to(x1, y1)


# ---------- the wallpaper and the menu on each system ----------

class Linux:
    def __init__(self, args):
        self.app = os.path.expanduser("~/.local/share/persona-desktop/app/persona_desktop.py")
        self.wall = args.wallpaper or os.path.expanduser("~/.local/share/persona-desktop/wallpaper")
        self.hidden = []

    def reload(self):
        subprocess.run([self.app, "--reload"])

    def js(self, code):
        subprocess.run([self.app, "--js", code])

    def menu(self, open_, place=None):
        if place:
            self.js("PD.placeMenu(%d, %d)" % tuple(place))
        self.js("PD.open(%s)" % ("true" if open_ else "false"))

    def prop(self, name, val):
        self.js("livelyPropertyListener(%s, %s)" % (json.dumps(name), json.dumps(val)))

    def show_desktop(self):
        ids = subprocess.run(["xdotool", "search", "--onlyvisible", "--name", ""], capture_output=True, text=True).stdout.split()
        for w in ids:
            t = subprocess.run(["xprop", "-id", w, "_NET_WM_WINDOW_TYPE"], capture_output=True, text=True).stdout
            if "_NET_WM_WINDOW_TYPE_NORMAL" in t or "not found" in t and "WM_STATE" in subprocess.run(["xprop", "-id", w, "WM_STATE"], capture_output=True, text=True).stdout:
                subprocess.run(["xdotool", "windowminimize", w])
                self.hidden.append(w)

    def restore(self):
        for w in reversed(self.hidden):
            subprocess.run(["xdotool", "windowactivate", w], stderr=subprocess.DEVNULL)
        self.hidden = []

    def capture(self, path, w, h, fps):
        cmd = ["ffmpeg", "-hide_banner", "-y", "-f", "x11grab", "-framerate", str(fps), "-video_size", "%dx%d" % (w, h), "-draw_mouse", "1",
               "-i", os.environ.get("DISPLAY", ":0") + "+0,0"]
        src = pulse_monitor()
        if src:
            cmd += ["-f", "pulse", "-i", src, "-c:a", "aac", "-b:a", "192k"]
        return cmd + ["-c:v", "libx264", "-preset", "ultrafast", "-crf", "16", "-pix_fmt", "yuv420p", path]


class Windows:
    def __init__(self, args):
        local = os.environ.get("LOCALAPPDATA", "")
        self.wall = args.wallpaper or os.path.join(local, "Lively Wallpaper", "Library", "wallpapers", "persona-monorail")
        self.lively = args.lively or os.path.join(local, "Programs", "Lively Wallpaper", "Lively.exe")
        self.rainmeter = os.path.join(os.environ.get("ProgramFiles", r"C:\Program Files"), "Rainmeter", "Rainmeter.exe")

    def reload(self):
        subprocess.run([self.lively, "setwp", "--file", os.path.join(self.wall, "index.html")])

    def js(self, code):
        pass

    def menu(self, open_, place=None):
        if place:
            subprocess.run([self.rainmeter, "!Move", str(place[0]), str(place[1]), "PersonaMenu"])
        v = "1" if open_ else "0"
        subprocess.run([self.rainmeter, "!SetVariable", "MenuOpen", v, "PersonaMenu"])
        subprocess.run([self.rainmeter, "!UpdateMeasure", "MeasureMenu", "PersonaMenu"])

    def prop(self, name, val):
        subprocess.run([self.lively, "setprop", "--property", "%s=%s" % (name, json.dumps(val))])

    def show_desktop(self):
        k = ctypes.windll.user32.keybd_event
        k(0x5B, 0, 0, 0); k(0x44, 0, 0, 0); k(0x44, 0, 2, 0); k(0x5B, 0, 2, 0)

    def restore(self):
        self.show_desktop()

    def capture(self, path, w, h, fps):
        return ["ffmpeg", "-hide_banner", "-y", "-f", "gdigrab", "-framerate", str(fps), "-draw_mouse", "1", "-offset_x", "0", "-offset_y", "0",
                "-video_size", "%dx%d" % (w, h), "-i", "desktop", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "16", "-pix_fmt", "yuv420p", path]


def pulse_monitor():
    out = subprocess.run(["ffmpeg", "-hide_banner", "-sources", "pulse"], capture_output=True, text=True)
    m = re.search(r"^\*?\s*(\S+\.monitor)\b", out.stdout + out.stderr, re.M)
    return m.group(1) if m else None


# ---------- shots ----------

def run_shot(sys_, shot, cfg, out_dir, offset):
    name = shot["name"]
    fps, (w, h) = cfg["fps"], cfg["screen"]
    rec = dict(cfg["record"])
    rec["sync"] = bool(shot.get("sync"))
    rec["loop"] = cfg["loop"]
    rec["offset"] = round(offset, 4)
    with open(os.path.join(sys_.wall, "record.js"), "w", encoding="utf-8") as f:
        f.write("window.PD_RECORD = " + json.dumps(rec) + ";\n")
    print("\n>> %s: %s" % (name, shot.get("about", "")))
    sys_.show_desktop()
    sys_.reload()
    time.sleep(6)
    for k, v in shot.get("props", {}).items():
        sys_.prop(k, v)
    sys_.menu(bool(shot.get("menuOpen")), cfg.get("menuAt"))
    x, y = shot.get("start", [1180, 560])
    mouse_to(x, y)
    time.sleep(1.0)

    steps = shot["steps"]
    # When does the event we line up on happen, counted from the first step?
    lead, t = None, 0.0
    for s in steps:
        if s[0] in ("click",) and len(s) > 1 and s[1] == shot.get("phaseAt"):
            lead = t
        t += {"wait": lambda s: s[1], "move": lambda s: s[3]}.get(s[0], lambda s: 0.06)(s)
    total = t

    path = os.path.join(out_dir, "%s-%s.mp4" % (OS, name))
    proc = subprocess.Popen(sys_.capture(path, w, h, fps), stdin=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8", errors="replace")
    start_wall, err_lines = None, []
    deadline = time.time() + 10
    while time.time() < deadline:
        line = proc.stderr.readline()
        if not line:
            break
        err_lines.append(line)
        m = re.search(r"start: (\d+\.\d+)", line)
        if m and float(m.group(1)) > 1e9:
            start_wall = float(m.group(1))
        if line.startswith("Output #0") or "Press [q]" in line:
            break
    import threading
    threading.Thread(target=lambda: [err_lines.append(l) for l in proc.stderr], daemon=True).start()
    if start_wall is None:
        start_wall = time.time()
        print("  ! ffmpeg didn't say when it started, event times are approximate.")
    time.sleep(cfg.get("preRoll", 1.0))

    # Start the steps so the lined-up event happens at the same point of the wallpaper's loop on every computer.
    begin = time.time() + 0.3
    if lead is not None and "phase" in shot:
        loop = cfg["loop"]
        real = begin + offset + lead
        wait = (shot["phase"] - real % loop) % loop
        begin += wait
        print("  waiting %.1fs so the wallpaper lines up..." % wait)
    sleep_until(begin)

    events = {}
    t = begin
    for s in steps:
        kind = s[0]
        if kind == "wait":
            t += s[1]
            sleep_until(t)
        elif kind == "move":
            glide(s[1], s[2], s[3], t)
            t += s[3]
            sleep_until(t)
        elif kind == "at":
            mouse_to(s[1], s[2])
        elif kind == "click":
            sleep_until(t)
            click()
            if len(s) > 1:
                events[s[1]] = round(t - start_wall, 4)
                print("  %s at %.2fs" % (s[1], t - start_wall))
            t += 0.06
        elif kind == "js":
            sys_.js(s[1])
        elif kind == "prop":
            sys_.prop(s[1], s[2])
        elif kind == "mark":
            events[s[1]] = round(time.time() - start_wall, 4)
    time.sleep(cfg.get("postRoll", 1.0))
    proc.stdin.write("q")
    proc.stdin.flush()
    proc.wait(timeout=60)
    meta = {"shot": name, "os": OS, "file": os.path.basename(path), "events": events, "phase": shot.get("phase"),
            "loop": cfg["loop"], "ntpOffset": offset, "screen": [w, h], "fps": fps}
    with open(path[:-4] + ".json", "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)
    print("  saved %s" % path)
    return meta


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--shots", default=os.path.join(HERE, "shots.json"))
    ap.add_argument("--out", default=os.path.join(HERE, "clips"))
    ap.add_argument("--only", help="comma separated shot names")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--wallpaper", help="folder with the wallpaper's index.html (found automatically)")
    ap.add_argument("--lively", help="path to Lively.exe (Windows, found automatically)")
    args = ap.parse_args()
    with open(args.shots, encoding="utf-8") as f:
        cfg = json.load(f)
    shots = [s for s in cfg["shots"] if OS in s["platforms"]]
    if args.only:
        want = args.only.split(",")
        shots = [s for s in shots if s["name"] in want]
    if args.list:
        for s in shots:
            print("%-10s %s" % (s["name"], s.get("about", "")))
        return
    if not shutil.which("ffmpeg"):
        sys.exit("ffmpeg isn't installed (or not on PATH).")
    w, h = screen_size()
    if [w, h] != cfg["screen"]:
        sys.exit("The screen is %dx%d but the shots are made for %dx%d. Change the display resolution (and 100%% scaling on Windows) first." % (w, h, *cfg["screen"]))
    sys_ = Windows(args) if WIN else Linux(args)
    if not os.path.exists(os.path.join(sys_.wall, "index.html")):
        sys.exit("Couldn't find the wallpaper at %s (use --wallpaper)." % sys_.wall)
    os.makedirs(args.out, exist_ok=True)
    print("Checking the clock against NTP...")
    offset = ntp_offset()
    print("  this computer's clock is off by %+.3fs" % -offset)
    print("Recording %d shots. Hands off the mouse until it says DONE." % len(shots))
    time.sleep(2)
    results = []
    try:
        for s in shots:
            results.append(run_shot(sys_, s, cfg, args.out, offset))
    finally:
        try:
            os.remove(os.path.join(sys_.wall, "record.js"))
        except OSError:
            pass
        sys_.menu(False)
        sys_.reload()
        time.sleep(1)
        sys_.restore()
    print("\nDONE. Clips are in %s" % args.out)


if __name__ == "__main__":
    main()
