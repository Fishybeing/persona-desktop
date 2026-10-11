(function () {
  const $ = (id) => document.getElementById(id);
  const opts = { darkHour: 0, showCalendar: true, showPlayer: true, showCredit: true, clock24: true, volume: 60 };
  const flags = location.hash.replace("#", "").split(",");
  const forced = flags.includes("darkhour") ? "darkhour" : flags.includes("normal") ? "normal" : "";
  if (flags.includes("notrans")) document.documentElement.classList.add("notrans");
  if (flags.includes("still")) document.body.classList.add("still");
  const vids = Array.from(document.querySelectorAll("#bg video")), FADE = 1.5;
  let curVid = 0, fading = false;
  const animated = () => !document.body.classList.contains("still");
  vids.forEach((v, i) => {
    v.addEventListener("play", () => { if ((i !== curVid && !fading) || !animated()) v.pause(); });
    v.addEventListener("timeupdate", () => {
      if (i !== curVid || fading || !v.duration || v.currentTime < v.duration - FADE - 0.35) return;
      fading = true;
      const n = vids[1 - curVid];
      n.style.transition = "none";
      n.style.zIndex = 2;
      v.style.zIndex = 1;
      n.currentTime = 0;
      n.play().catch(() => {});
      requestAnimationFrame(() => { n.style.transition = "opacity " + FADE + "s linear"; n.classList.add("on"); });
      setTimeout(() => { v.pause(); v.style.transition = "none"; v.classList.remove("on"); curVid = 1 - curVid; fading = false; }, FADE * 1000 + 120);
    });
    v.addEventListener("ended", () => { if (i === curVid && !fading) { v.currentTime = 0; v.play().catch(() => {}); } });
  });
  if (vids.length) vids[0].classList.add("on");
  function setAnimated(on) {
    document.body.classList.toggle("still", !on);
    if (!vids.length) return;
    if (on) vids[curVid].play().catch(() => {}); else vids.forEach(v => v.pause());
  }
  let dark = null, audioBands = new Array(64).fill(0), audioSeen = 0;

  function isDark(now) {
    if (forced === "darkhour") return true;
    if (forced === "normal") return false;
    if (opts.darkHour === 1) return true;
    if (opts.darkHour === 2) return false;
    return now.getHours() === 0;
  }

  function setMode(d) {
    if (d === dark) return;
    dark = d;
    document.body.classList.toggle("darkhour", dark);
    if (dark) { document.body.classList.add("intro"); setTimeout(() => document.body.classList.remove("intro"), 7000); }
    else document.body.classList.remove("intro");
  }

  const DOW = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
  function slotName(d) {
    const h = d.getHours(), sunday = d.getDay() === 0;
    if (isDark(d)) return "DARK HOUR";
    if (h < 5) return "LATE NIGHT";
    if (h < 7) return "EARLY MORNING";
    if (sunday && h < 18) return "DAYTIME";
    if (h < 12) return "MORNING";
    if (h < 13) return "LUNCHTIME";
    if (h < 15) return "AFTERNOON";
    if (h < 18) return "AFTER SCHOOL";
    return "EVENING";
  }

  const SYN = 29.530588853;
  function moonAge(d) { const ref = Date.UTC(2000, 0, 6, 18, 14); return (((d.getTime() - ref) / 86400000) % SYN + SYN) % SYN; }

  function drawPhase(age) {
    const c = $("moonc"), g = c.getContext("2d"), s = c.width, r = s * 0.42, cx = s / 2, cy = s / 2;
    g.clearRect(0, 0, s, s);
    const f = age / SYN, sd = f < 0.5 ? 1 : -1, cs = Math.cos(f * Math.PI * 2), ex = Math.abs(cs) * r;
    g.fillStyle = dark ? "#e2f59a" : "#f4f8ff";
    g.beginPath(); g.arc(cx, cy, r, -Math.PI / 2, Math.PI / 2, sd < 0); g.fill();
    if (cs > 0) {
      g.globalCompositeOperation = "destination-out";
      g.beginPath(); g.ellipse(cx, cy, ex + 0.5, r + 0.5, 0, -Math.PI / 2, Math.PI / 2, sd < 0); g.fill();
      g.globalCompositeOperation = "source-over";
    } else {
      g.beginPath(); g.ellipse(cx, cy, ex, r, 0, -Math.PI / 2, Math.PI / 2, sd > 0); g.fill();
    }
    g.globalCompositeOperation = "destination-over";
    g.fillStyle = "rgba(255,255,255,0.14)";
    g.beginPath(); g.arc(cx, cy, r, 0, Math.PI * 2); g.fill();
    g.globalCompositeOperation = "source-over";
  }

  function phaseText(age) {
    const toFull = (14.765 - age + SYN) % SYN;
    if (toFull < 1 || toFull > SYN - 1) return "FULL MOON TONIGHT";
    if (age < 1 || age > SYN - 1) return "NEW MOON";
    const n = Math.round(toFull);
    return "FULL MOON IN " + n + (n === 1 ? " DAY" : " DAYS");
  }

  function tickCal() {
    const d = new Date();
    setMode(isDark(d));
    $("md").textContent = (d.getMonth() + 1) + "/" + d.getDate();
    $("dow").textContent = DOW[d.getDay()];
    $("dow").classList.toggle("sun", d.getDay() === 0 && !dark);
    $("slot").textContent = slotName(d);
    const age = moonAge(d);
    drawPhase(age);
    $("phase").textContent = phaseText(age);
    const mm = String(d.getMinutes()).padStart(2, "0");
    if (dark) $("clock").textContent = "--:--";
    else if (opts.clock24) $("clock").textContent = String(d.getHours()).padStart(2, "0") + ":" + mm;
    else $("clock").innerHTML = ((d.getHours() % 12) || 12) + ":" + mm + "<small>" + (d.getHours() < 12 ? "AM" : "PM") + "</small>";
    let w = "";
    if (!dark && d.getHours() === 23 && opts.darkHour === 0) w = "DARK HOUR IN " + (60 - d.getMinutes()) + " MIN";
    if (dark) w = "THE 25TH HOUR";
    $("warn").textContent = w;
  }

  const audio = new Audio();
  audio.preload = "metadata";
  const tracks = (window.P3_PLAYLIST || []).filter(x => x && x.file);
  const store = {
    get(k, d) { try { const v = localStorage.getItem("mr_" + k); return v === null ? d : JSON.parse(v); } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem("mr_" + k, JSON.stringify(v)); } catch (e) {} }
  };
  let order = [], opos = 0;
  const gameCount = {};
  tracks.forEach(x => { if (x.game) gameCount[x.game] = (gameCount[x.game] || 0) + 1; });
  const bigGames = Object.keys(gameCount).filter(g => gameCount[g] >= 3).sort();
  const filters = ["ALL"];
  if (tracks.some(x => /^PERSONA/i.test(x.game || ""))) filters.push("PERSONA");
  bigGames.forEach(g => filters.push(g));
  if (tracks.some(x => !bigGames.includes(x.game || "") && !/^PERSONA/i.test(x.game || ""))) filters.push("OTHER");
  function inFilter(x, f) {
    if (f === "ALL") return true;
    if (f === "PERSONA") return /^PERSONA/i.test(x.game || "");
    if (f === "OTHER") return !bigGames.includes(x.game || "") && !/^PERSONA/i.test(x.game || "");
    return x.game === f;
  }
  let filter = "ALL", pool = [];
  let idx = Math.min(store.get("idx", 0), Math.max(0, tracks.length - 1)), shuffle = store.get("shuf", false), repeat = store.get("rep", true), userVol = store.get("vol", null), muted = store.get("mute", false), pcTrack = null;
  let actx = null, gain = null, analyser = null, freq = null;

  function initAudioGraph() {
    if (actx) return;
    try {
      const AC = window.AudioContext || window.webkitAudioContext;
      actx = new AC();
      const src = actx.createMediaElementSource(audio);
      gain = actx.createGain();
      analyser = actx.createAnalyser();
      analyser.fftSize = 2048;
      analyser.smoothingTimeConstant = 0.55;
      freq = new Uint8Array(analyser.frequencyBinCount);
      src.connect(analyser);
      src.connect(gain);
      gain.connect(actx.destination);
      audio.volume = 1;
      applyVol();
    } catch (e) { actx = null; gain = null; analyser = null; }
  }
  function wake() { initAudioGraph(); if (actx && actx.state === "suspended") actx.resume().catch(() => {}); }

  function fmt(s) { if (!isFinite(s)) return "0:00"; s = Math.floor(s); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }
  const SPEAKER = '<path d="M4 9h4l5-4v14l-5-4H4zM16 8.5a5 5 0 0 1 0 7l-1.4-1.4a3 3 0 0 0 0-4.2zM18.4 6a8.5 8.5 0 0 1 0 12L17 16.6a6.5 6.5 0 0 0 0-9.2z"/>';
  const SPEAKER_OFF = '<path d="M4 9h4l5-4v14l-5-4H4zM16.3 9.1l1.4-1.4 2.3 2.3 2.3-2.3 1.4 1.4-2.3 2.3 2.3 2.3-1.4 1.4-2.3-2.3-2.3 2.3-1.4-1.4 2.3-2.3z"/>';
  function vol() { return Math.max(0, Math.min(100, userVol === null ? opts.volume : userVol)) / 100; }
  function applyVol() {
    const v = vol(), out = muted ? 0 : v * v;
    if (gain && actx) gain.gain.setTargetAtTime(out, actx.currentTime, 0.03);
    else audio.volume = out;
    $("volfill").style.width = (v * 100) + "%";
    $("volknob").style.left = (v * 100) + "%";
    $("volpct").textContent = muted ? "MUTE" : Math.round(v * 100);
    $("vol").classList.toggle("muted", muted);
    $("mute").classList.toggle("on", muted);
    $("muteicon").innerHTML = muted || v === 0 ? SPEAKER_OFF : SPEAKER;
  }
  function setVol(pct) { userVol = Math.round(Math.max(0, Math.min(100, pct))); if (userVol > 0) muted = false; store.set("vol", userVol); store.set("mute", muted); applyVol(); }

  function showLocal() {
    const tr = tracks[idx];
    $("tag").textContent = "NOW PLAYING";
    $("src").textContent = "LOCAL · " + (pool.includes(idx) ? (pool.indexOf(idx) + 1) + "/" + pool.length : (idx + 1) + "/" + tracks.length) + (grid.bpm ? " · " + grid.bpm + " BPM" : "");
    $("title").textContent = tr.title || tr.file;
    const ar = $("artist");
    ar.textContent = "";
    if (tr.game) { const g = document.createElement("span"); g.className = "game"; g.textContent = tr.game; ar.appendChild(g); }
    if (tr.artist) ar.appendChild(document.createTextNode((tr.game ? "  ·  " : "") + tr.artist));
    $("hint").hidden = true;
  }

  function showIdle() {
    if (pcTrack && pcTrack.Title && audio.paused) {
      $("src").textContent = "ON THIS PC";
      $("title").textContent = pcTrack.Title;
      $("artist").textContent = pcTrack.Artist || "";
      return;
    }
    if (tracks.length) { showLocal(); return; }
    $("title").textContent = "No music yet";
    $("artist").textContent = "";
    $("hint").hidden = false;
    $("hint").textContent = "Put your music in the music folder and run Update playlist.";
  }

  function load(i, autoplay) {
    if (!tracks.length) return;
    idx = (i + tracks.length) % tracks.length;
    audio.src = tracks[idx].file;
    analyzeTrack(tracks[idx].file);
    store.set("idx", idx);
    showLocal();
    if (autoplay) { wake(); audio.play().catch(() => {}); }
  }

  function reshuffle(first) {
    order = pool.filter(i => i !== first);
    for (let i = order.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [order[i], order[j]] = [order[j], order[i]]; }
    if (pool.includes(first)) { order.unshift(first); opos = 0; } else opos = -1;
  }

  function filterLabel(f) {
    const n = f === "ALL" ? tracks.length : pool.length;
    return (f === "ALL" ? "ALL MUSIC" : f === "OTHER" ? "OTHER MUSIC" : f) + " \u00b7 " + n;
  }

  function setFilter(f, fromUser) {
    filter = filters.includes(f) ? f : "ALL";
    pool = tracks.map((x, i) => inFilter(x, filter) ? i : -1).filter(i => i >= 0);
    order = [];
    store.set("filter", filter);
    $("filt").textContent = filterLabel(filter);
    $("filt").classList.toggle("on", filter !== "ALL");
    if (fromUser && pool.length && !pool.includes(idx)) {
      const playing = !audio.paused;
      load(shuffle ? pool[Math.floor(Math.random() * pool.length)] : pool[0], playing);
    } else if (tracks.length) showLocal();
  }

  function nextIdx(dir) {
    if (!pool.length) return idx;
    if (!shuffle || pool.length < 2) {
      const p = pool.indexOf(idx);
      if (p < 0) return pool[0];
      return pool[(p + dir + pool.length) % pool.length];
    }
    if (!order.length || order[opos] !== idx) reshuffle(idx);
    opos += dir;
    if (opos >= order.length) {
      const last = order[order.length - 1];
      reshuffle(pool[Math.floor(Math.random() * pool.length)]);
      if (order[0] === last && order.length > 1) { const j = 1 + Math.floor(Math.random() * (order.length - 1)); [order[0], order[j]] = [order[j], order[0]]; }
    } else if (opos < 0) opos = 0;
    return order[opos];
  }

  function setPlayIcon() {
    $("playicon").innerHTML = audio.paused ? '<path d="M7 4v16l13-8z"/>' : '<path d="M6 4h4v16H6zM14 4h4v16h-4z"/>';
  }

  $("play").addEventListener("click", () => {
    if (!tracks.length) return;
    wake();
    if (!audio.src) load(idx, true);
    else if (audio.paused) audio.play().catch(() => {}); else audio.pause();
  });
  $("next").addEventListener("click", () => load(nextIdx(1), true));
  $("prev").addEventListener("click", () => { if (audio.currentTime > 3) audio.currentTime = 0; else load(nextIdx(-1), true); });
  $("shuf").addEventListener("click", () => { shuffle = !shuffle; store.set("shuf", shuffle); $("shuf").classList.toggle("on", shuffle); if (shuffle) reshuffle(idx); });
  $("rep").addEventListener("click", () => { repeat = !repeat; store.set("rep", repeat); $("rep").classList.toggle("on", repeat); });
  $("bar").addEventListener("click", (e) => { const r = $("bar").getBoundingClientRect(); if (audio.duration) audio.currentTime = (e.clientX - r.left) / r.width * audio.duration; });
  const volhit = $("volhit");
  let dragging = false;
  function volFromEvent(e) { const r = $("volbar").getBoundingClientRect(); setVol((e.clientX - r.left) / r.width * 100); }
  volhit.addEventListener("pointerdown", (e) => { dragging = true; try { volhit.setPointerCapture(e.pointerId); } catch (x) {} volFromEvent(e); e.preventDefault(); });
  volhit.addEventListener("pointermove", (e) => { if (dragging) volFromEvent(e); });
  const endDrag = () => { dragging = false; };
  volhit.addEventListener("pointerup", endDrag);
  volhit.addEventListener("pointercancel", endDrag);
  window.addEventListener("mouseup", endDrag);
  $("player").addEventListener("wheel", (e) => { e.preventDefault(); setVol(vol() * 100 + (e.deltaY < 0 ? 5 : -5)); }, { passive: false });
  $("mute").addEventListener("click", () => { muted = !muted; if (!muted && vol() === 0) userVol = 30; store.set("mute", muted); store.set("vol", userVol); applyVol(); });
  audio.addEventListener("play", setPlayIcon);
  audio.addEventListener("pause", () => { setPlayIcon(); showIdle(); });
  audio.addEventListener("ended", () => { if (pool.indexOf(idx) < pool.length - 1 || repeat || shuffle) load(nextIdx(1), true); });
  $("filt").addEventListener("click", () => { if (filters.length > 1) setFilter(filters[(filters.indexOf(filter) + 1) % filters.length], true); });
  $("filt").addEventListener("contextmenu", (e) => { e.preventDefault(); if (filters.length > 1) setFilter(filters[(filters.indexOf(filter) - 1 + filters.length) % filters.length], true); });
  audio.addEventListener("timeupdate", () => {
    $("fill").style.width = audio.duration ? (audio.currentTime / audio.duration * 100) + "%" : "0";
    $("cur").textContent = fmt(audio.currentTime); $("dur").textContent = fmt(audio.duration);
    if (Math.floor(audio.currentTime) % 5 === 0) store.set("pos", audio.currentTime);
  });
  audio.addEventListener("error", () => { if (tracks.length > 1) setTimeout(() => load(nextIdx(1), true), 800); });

  const vz = $("viz"), vctx = vz.getContext("2d"), player = $("player");
  const BARS = 48, bars = new Float32Array(BARS), peaks = new Float32Array(BARS), edges = [];
  let beat = 0, lastFrame = 0, accent = "#4cc3ff", accentAt = 0;

  function sizeViz() {
    const r = player.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
    vz.width = Math.max(200, Math.round(r.width * dpr));
    vz.height = Math.max(80, Math.round(r.height * dpr));
  }
  window.addEventListener("resize", sizeViz);

  function buildEdges() {
    if (!analyser || edges.length) return;
    const nyq = actx.sampleRate / 2, bins = analyser.frequencyBinCount, lo = 32, hi = 14000;
    for (let i = 0; i <= BARS; i++) {
      const f = lo * Math.pow(hi / lo, i / BARS);
      edges.push(Math.min(bins - 1, Math.max(1, Math.round(f / nyq * bins))));
    }
  }

  function readBands() {
    if (analyser && !audio.paused) {
      buildEdges();
      analyser.getByteFrequencyData(freq);
      for (let i = 0; i < BARS; i++) {
        let s = 0;
        for (let k = edges[i]; k <= Math.max(edges[i], edges[i + 1] - 1); k++) s = Math.max(s, freq[k]);
        bars[i] = Math.min(1, Math.pow(s / 255, 1.6) * (0.85 + 0.35 * i / BARS) * 1.15);
      }
      const binHz = actx.sampleRate / 2 / analyser.frequencyBinCount;
      let bass = 0, c = 0;
      for (let k = Math.max(1, Math.floor(40 / binHz)); k <= Math.ceil(140 / binHz); k++) { bass += freq[k] * freq[k]; c++; }
      return c ? bass / c / 65025 : 0;
    }
    if (performance.now() - audioSeen < 1500) {
      for (let i = 0; i < BARS; i++) bars[i] = Math.min(1, audioBands[Math.floor(i / BARS * audioBands.length)]);
      return (audioBands[0] + audioBands[1] + audioBands[2] + audioBands[3]) / 4;
    }
    bars.fill(0);
    return -1;
  }

  const GRID_V = 5, gridCache = {};
  const grid = { file: null, beats: null, str: null, bpm: 0, next: 0, half: false };

  function showBpm() {
    if (audio.paused && pcTrack && pcTrack.Title) return;
    if (!tracks.length) return;
    $("src").textContent = "LOCAL \u00b7 " + (pool.includes(idx) ? (pool.indexOf(idx) + 1) + "/" + pool.length : (idx + 1) + "/" + tracks.length) + (grid.bpm ? " \u00b7 " + grid.bpm + " BPM" : "");
  }

  function applyGrid(file, res) {
    if (grid.file !== file) return;
    gridCache[file] = res;
    if (res.beats && res.beats.length) {
      let acc = 0;
      grid.beats = res.beats.map(d => (acc += d) / 1000);
      grid.str = res.str.split("").map(Number);
      grid.bpm = res.bpm;
      grid.half = res.bpm > 165;
    }
    grid.next = 0;
    showBpm();
  }

  async function analyzeTrack(file) {
    grid.file = file; grid.beats = null; grid.str = null; grid.bpm = 0; grid.next = 0;
    showBpm();
    const cached = gridCache[file] || store.get("g" + GRID_V + "_" + file, null);
    if (cached) { applyGrid(file, cached); return; }
    try {
      const raw = await (await fetch(file)).arrayBuffer();
      if (grid.file !== file) return;
      const SR = 11025, off = new OfflineAudioContext(1, SR, SR);
      const buf = await off.decodeAudioData(raw);
      if (grid.file !== file) return;
      const res = beatTrack(buf, SR);
      store.set("g" + GRID_V + "_" + file, res);
      applyGrid(file, res);
    } catch (e) {}
  }

  function beatTrack(buf, SR) {
    const n = buf.length, ch = buf.numberOfChannels, x = new Float32Array(n);
    for (let c = 0; c < ch; c++) { const d = buf.getChannelData(c); for (let i = 0; i < n; i++) x[i] += d[i] / ch; }
    const hop = 128, fps = SR / hop, F = Math.floor(n / hop);
    const lowE = new Float32Array(F), highE = new Float32Array(F);
    const k = 1 - Math.exp(-2 * Math.PI * 180 / SR);
    let lp = 0;
    for (let f = 0; f < F; f++) {
      let el = 0, eh = 0;
      for (let i = f * hop, e = i + hop; i < e; i++) { lp += k * (x[i] - lp); const h = x[i] - lp; el += lp * lp; eh += h * h; }
      lowE[f] = Math.log(1 + 1000 * el / hop); highE[f] = Math.log(1 + 1000 * eh / hop);
    }
    const o = new Float32Array(F), loud = new Float32Array(F);
    for (let f = 1; f < F; f++) {
      o[f] = Math.max(0, lowE[f] - lowE[f - 1]) + 0.5 * Math.max(0, highE[f] - highE[f - 1]);
      loud[f] = lowE[f] + highE[f];
    }
    const W = Math.round(fps * 0.4), on = new Float32Array(F);
    let run = 0;
    for (let f = 0; f < F; f++) {
      run += o[f] - (f >= 2 * W ? o[f - 2 * W] : 0);
      const c = f - W;
      if (c >= 0) on[c] = Math.max(0, o[c] - run / (2 * W));
    }
    let mean = 0, sd = 0;
    for (let f = 0; f < F; f++) mean += on[f];
    mean /= F || 1;
    for (let f = 0; f < F; f++) sd += (on[f] - mean) * (on[f] - mean);
    sd = Math.sqrt(sd / (F || 1)) || 1;
    for (let f = 0; f < F; f++) on[f] /= sd;

    const minLag = Math.floor(fps * 60 / 190), maxLag = Math.ceil(fps * 60 / 70), top = 2 * maxLag + 2, ac = new Float32Array(top + 2);
    for (let L = Math.max(1, Math.floor(minLag / 2) - 1); L <= top + 1; L++) { let s = 0; for (let f = L; f < F; f++) s += on[f] * on[f - L]; ac[L] = s; }
    const refine = (L) => { const y0 = ac[L - 1], y1 = ac[L], y2 = ac[L + 1], den = y0 - 2 * y1 + y2; return L + (den ? Math.max(-0.5, Math.min(0.5, 0.5 * (y0 - y2) / den)) : 0); };
    let best = 0, bestScore = -1;
    for (let L = minLag; L <= maxLag; L++) {
      const bpm = 60 * fps / L, w = Math.exp(-0.5 * Math.pow(Math.log2(bpm / 125) / 0.8, 2));
      const sc = w * (ac[L] + 0.5 * ac[2 * L]);
      if (sc > bestScore && ac[L] >= ac[L - 1] && ac[L] >= ac[L + 1]) { bestScore = sc; best = L; }
    }
    if (!best) return { bpm: 0, beats: [], str: "", conf: 0 };
    if (60 * fps / best < 100 && 60 * fps / (best / 2) <= 190) {
      let hb = Math.round(best / 2);
      for (let L = hb - 1; L <= hb + 1; L++) if (ac[L] > ac[hb]) hb = L;
      if (ac[hb] > 0.5 * ac[best]) best = hb;
    }
    const P = refine(best);
    function track(P) {
      const score = new Float32Array(F), back = new Int32Array(F).fill(-1), lo = Math.round(P / 2), hi = Math.round(2 * P), pen = new Float32Array(hi + 1);
      for (let d = lo; d <= hi; d++) { const r = Math.log(d / P); pen[d] = 400 * r * r; }
      for (let f = 0; f < F; f++) {
        let m = 0, arg = -1;
        for (let d = lo; d <= hi && d <= f; d++) { const v = score[f - d] - pen[d]; if (arg < 0 || v > m) { m = v; arg = f - d; } }
        score[f] = on[f] + (arg >= 0 && m > 0 ? m : 0);
        back[f] = arg >= 0 && m > 0 ? arg : -1;
      }
      let end = F - 1, es = -1;
      for (let f = Math.max(0, F - Math.round(P)); f < F; f++) if (score[f] > es) { es = score[f]; end = f; }
      const fr = [];
      for (let f = end; f >= 0; f = back[f]) fr.push(f);
      return fr.reverse();
    }
    const frames = track(P);
    const sorted = Array.from(loud).sort((p, q) => p - q), lq = sorted[Math.floor(F * 0.3)] || 0, hq = sorted[Math.floor(F * 0.95)] || 1;
    const beats = [], str = [];
    let prev = 0;
    for (const f of frames) {
      let pk = 0, lv = 0;
      for (let j = Math.max(0, f - 2); j <= Math.min(F - 1, f + 2); j++) { pk = Math.max(pk, on[j]); lv = Math.max(lv, loud[j]); }
      const level = Math.max(0, Math.min(1, (lv - lq) / Math.max(0.001, hq - lq)));
      const hit = Math.max(0, Math.min(1, (pk - 0.8) / 1.7));
      const ms = Math.round(f * hop / SR * 1000);
      beats.push(ms - prev); prev = ms;
      str.push(Math.round(Math.min(1, level * hit) * 9));
    }
    return { bpm: Math.round(60 * fps / P), beats, str: str.join(""), conf: 0 };
  }

  function stepBeat(energy) {
    const B = grid.beats;
    if (!B || audio.paused) return;
    const now = audio.currentTime + 0.015;
    let i = grid.next;
    if (i > B.length || (i < B.length && B[i] - now > 2) || (i > 0 && B[i - 1] > now + 0.05)) {
      let lo = 0, hi = B.length;
      while (lo < hi) { const m = (lo + hi) >> 1; if (B[m] < now - 0.05) lo = m + 1; else hi = m; }
      i = lo;
    }
    while (i < B.length && B[i] <= now) {
      const s = grid.str[i] / 9;
      if (now - B[i] < 0.1 && s >= 0.3 && energy > 0.01 && (!grid.half || i % 2 === 0)) beat = Math.max(beat, 0.3 + 0.7 * s);
      i++;
    }
    grid.next = i;
  }

  function drawViz(now) {
    requestAnimationFrame(drawViz);
    if (!opts.showPlayer) return;
    const dt = Math.min(0.1, (now - (lastFrame || now)) / 1000);
    lastFrame = now;
    if (now - accentAt > 1000) { accent = getComputedStyle(document.body).getPropertyValue("--accent").trim() || "#4cc3ff"; accentAt = now; }
    const energy = readBands();
    stepBeat(energy);
    beat = Math.max(0, beat - dt * 3.2);
    player.style.setProperty("--beat", beat.toFixed(3));
    const w = vz.width, h = vz.height;
    vctx.clearRect(0, 0, w, h);
    if (energy < 0 && !peaks.some(v => v > 0.01)) return;
    const bw = w / BARS, gap = Math.max(1, bw * 0.22);
    vctx.fillStyle = accent;
    for (let i = 0; i < BARS; i++) {
      const v = bars[i];
      peaks[i] = v > peaks[i] ? v : Math.max(0, peaks[i] - dt * 0.6);
      const bh = Math.max(2, v * h * (0.9 + beat * 0.1));
      vctx.globalAlpha = 0.75 + 0.25 * v;
      vctx.fillRect(i * bw + gap / 2, h - bh, bw - gap, bh);
      vctx.globalAlpha = 0.9;
      vctx.fillRect(i * bw + gap / 2, h - peaks[i] * h - 3, bw - gap, 2);
    }
    vctx.globalAlpha = 1;
  }

  window.livelyAudioListener = function (arr) {
    if (!arr || !arr.length) return;
    let any = 0;
    for (let i = 0; i < 64; i++) { const v = arr[Math.floor(i / 64 * arr.length)] || 0; audioBands[i] = audioBands[i] * 0.4 + Math.min(1, v * 1.4) * 0.6; any += v; }
    if (any > 0.01) audioSeen = performance.now();
  };
  window.livelyCurrentTrack = function (data) {
    try { pcTrack = data ? (typeof data === "string" ? JSON.parse(data) : data) : null; } catch (e) { pcTrack = null; }
    showIdle();
  };
  window.livelyPropertyListener = function (name, val) {
    if (name === "darkHour") opts.darkHour = Number(val) || 0;
    else if (name === "volume") { opts.volume = Number(val); if (userVol !== null && userVol !== opts.volume && performance.now() > 4000) { userVol = opts.volume; store.set("vol", userVol); } applyVol(); }
    else if (name === "animated") setAnimated(!!val);
    else if (name in opts) opts[name] = !!val;
    document.body.classList.toggle("noplayer", !opts.showPlayer);
    document.body.classList.toggle("nocal", !opts.showCalendar);
    document.body.classList.toggle("nocredit", !opts.showCredit);
    tickCal();
  };

  tickCal();
  setInterval(tickCal, 5000);
  $("shuf").classList.toggle("on", shuffle);
  $("rep").classList.toggle("on", repeat);
  applyVol();
  setFilter(store.get("filter", "ALL"), false);
  if (tracks.length && pool.length && !pool.includes(idx)) idx = pool[0];
  if (tracks.length) { load(idx, false); const p = store.get("pos", 0); audio.addEventListener("loadedmetadata", () => { if (p && p < audio.duration - 2) audio.currentTime = p; }, { once: true }); }
  showIdle();
  setPlayIcon();
  sizeViz();
  requestAnimationFrame(drawViz);
})();
