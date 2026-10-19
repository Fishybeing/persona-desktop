(function () {
  if (window.PD) return;
  const RES = "{RES}";
  const style = document.createElement("style");
  style.textContent = "{CSS}";
  document.head.appendChild(style);
  const SVGNS = "http://www.w3.org/2000/svg";
  const post = (o) => window.webkit.messageHandlers.pd.postMessage(JSON.stringify(o));
  const store = {
    get(k, d) { try { const v = localStorage.getItem("pd_" + k); return v === null ? d : JSON.parse(v); } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem("pd_" + k, JSON.stringify(v)); } catch (e) {} }
  };
  function el(tag, cls, parent) { const e = document.createElement(tag); if (cls) e.className = cls; if (parent) parent.appendChild(e); return e; }
  function shape(parent, w, h, points, cls, x, y) {
    const s = document.createElementNS(SVGNS, "svg");
    s.setAttribute("class", "pd-shape " + (cls || ""));
    s.setAttribute("width", w); s.setAttribute("height", h);
    s.setAttribute("viewBox", "0 0 " + w + " " + h);
    s.style.left = x + "px"; s.style.top = y + "px";
    const p = document.createElementNS(SVGNS, "polygon");
    p.setAttribute("points", points);
    s.appendChild(p);
    parent.appendChild(s);
    return s;
  }
  const sounds = {};
  function play(name) {
    const a = (sounds[name] = sounds[name] || new Audio(RES + "/menu/Sounds/" + name + ".wav"));
    try { const c = a.cloneNode(); c.volume = 0.8; c.play().catch(() => {}); } catch (e) {}
  }

  // Drag a skin around like Rainmeter does; a click without moving still counts as a click.
  function draggable(box, handle, key, onClick) {
    let start = null;
    handle.addEventListener("mousedown", (e) => {
      if (e.button !== 0) return;
      start = { x: e.clientX, y: e.clientY, left: box.offsetLeft, top: box.offsetTop, moved: false };
      e.preventDefault();
    });
    window.addEventListener("mousemove", (e) => {
      if (!start) return;
      const dx = e.clientX - start.x, dy = e.clientY - start.y;
      if (!start.moved && Math.abs(dx) + Math.abs(dy) < 5) return;
      start.moved = true;
      box.style.left = Math.max(0, Math.min(innerWidth - 40, start.left + dx)) + "px";
      box.style.top = Math.max(0, Math.min(innerHeight - 40, start.top + dy)) + "px";
    });
    window.addEventListener("mouseup", () => {
      if (!start) return;
      if (start.moved) store.set(key, [box.offsetLeft, box.offsetTop]);
      else if (onClick) onClick();
      start = null;
    });
  }

  const root = el("div", "pd-root", document.body);

  // ---------- Persona 5 menu (same layout as the Rainmeter one on Windows) ----------
  const colW = 300, rowH = 36, sk = 10, top = 64, headH = 46, pad = 18, gap = 14;
  const menu = el("div", "pd-menu", root);
  const tabBox = el("div", "pd-tab", menu);
  shape(tabBox, 188, 56, "12,6 182,6 170,50 0,50", "pd-tabshadow", -6, 0);
  shape(tabBox, 182, 44, "12,0 182,0 170,44 0,44", "pd-tabfill", 0, 0);
  el("div", "pd-tabtext", tabBox).textContent = "MENU";
  const panel = el("div", "pd-panel", menu);
  let open = false;
  function setOpen(o) {
    open = o;
    menu.classList.toggle("open", open);
    play(open ? "open" : "close");
  }
  tabBox.addEventListener("mouseenter", () => tabBox.classList.add("hover"));
  tabBox.addEventListener("mouseleave", () => tabBox.classList.remove("hover"));
  draggable(menu, tabBox, "menuPos", () => setOpen(!open));
  const mp = store.get("menuPos", [110, 36]);
  menu.style.left = mp[0] + "px"; menu.style.top = mp[1] + "px";

  function buildPanel(sections) {
    panel.textContent = "";
    sections.forEach(s => { s.h = headH + 6 + s.items.length * rowH + gap; });
    function pack(n) {
      const hs = new Array(n).fill(0);
      sections.forEach(s => {
        let c = 0;
        for (let k = 1; k < n; k++) if (hs[k] < hs[c]) c = k;
        s.col = c; s.y = hs[c]; hs[c] += s.h;
      });
      return hs;
    }
    let ncols = Math.max(1, Math.min(3, sections.length)), colH = pack(ncols);
    if (Math.max(...colH) > 720 && sections.length >= 4) { ncols = 4; colH = pack(ncols); }
    const room = innerHeight - menu.offsetTop - top - 50;
    while (Math.max(...colH) > room && ncols < sections.length && (ncols + 1) * (colW + 10) + menu.offsetLeft < innerWidth) { ncols++; colH = pack(ncols); }
    const panelW = ncols * colW + (ncols - 1) * 10 + 2 * pad + 10, panelH = Math.max(0, ...colH) + 34;
    shape(panel, panelW + 30, panelH + 4, (25.5) + ",1.5 " + (panelW + 25.5) + ",1.5 " + (panelW + 1.5) + "," + (panelH + 1.5) + " 1.5," + (panelH + 1.5), "pd-panelbg", -1.5, top - 1.5);
    sections.forEach(sec => {
      const cx = pad + 14 + sec.col * (colW + 10), sy = top + sec.y;
      const head = el("div", "pd-head", panel);
      head.textContent = sec.title;
      head.style.left = cx + "px"; head.style.top = (sy + 8) + "px";
      shape(panel, colW - 30, 5, "8,0 " + (colW - 30) + ",0 " + (colW - 38) + ",5 0,5", "pd-headline", cx, sy + headH - 4);
      sec.items.forEach((it, r) => {
        const y = sy + headH + 6 + r * rowH;
        const bar = shape(panel, colW - 12, rowH - 4, sk + ",0 " + (colW - 12) + ",0 " + (colW - 12 - sk) + "," + (rowH - 4) + " 0," + (rowH - 4), "pd-bar", cx - 8, y + 2);
        const row = el("div", "pd-item", panel);
        row.style.left = cx + "px"; row.style.top = (y + 2) + "px"; row.style.width = (colW - 20) + "px"; row.style.height = (rowH - 4) + "px";
        el("span", "", row).textContent = it.name;
        if (it.icon) {
          const img = el("img", "pd-icon", panel);
          img.src = it.icon;
          img.style.left = (cx + 4) + "px"; img.style.top = (y + 5) + "px";
          img.onerror = () => img.remove();
        }
        row.addEventListener("mouseenter", () => { bar.classList.add("on"); row.classList.add("on"); play("00121"); });
        row.addEventListener("mouseleave", () => { bar.classList.remove("on"); row.classList.remove("on"); });
        row.addEventListener("click", () => { play("00007"); post({ cmd: "launch", id: it.id }); });
      });
    });
    [["UPDATE LIST", "updateMenu", 110], ["SETTINGS", "settings", 200]].forEach(([label, cmd, off]) => {
      const b = el("div", "pd-link", panel);
      b.textContent = label;
      b.style.left = (panelW - off) + "px"; b.style.top = (top + panelH - 30) + "px";
      b.addEventListener("click", () => { play("00007"); post({ cmd }); });
    });
  }

  // ---------- Persona 5 system bars (ElysianAura's skin) ----------
  const sys = el("div", "pd-sys", root);
  el("img", "pd-sysbg", sys).src = RES + "/system/ramcpu.png";
  const cpuNum = el("div", "pd-num pd-cpu", sys), ramNum = el("div", "pd-num pd-ram", sys);
  const cpuBar = el("div", "pd-meter pd-cpubar", sys), ramBar = el("div", "pd-meter pd-rambar", sys);
  cpuBar.style.backgroundImage = "url('" + RES + "/system/cpupersona.png')";
  ramBar.style.backgroundImage = "url('" + RES + "/system/rampersona.png')";
  cpuNum.textContent = ramNum.textContent = "000";
  draggable(sys, sys, "sysPos", null);
  const sp = store.get("sysPos", null);
  if (sp) { sys.style.left = sp[0] + "px"; sys.style.top = sp[1] + "px"; }

  const pad3 = (n) => String(Math.max(0, Math.min(100, n))).padStart(3, "0");
  window.PD = {
    setMenu(sections) { buildPanel(sections || []); },
    setStats(cpu, ram) {
      cpuNum.textContent = pad3(cpu); ramNum.textContent = pad3(ram);
      cpuBar.style.width = (1.15 * cpu) + "px"; ramBar.style.width = (1.12 * ram) + "px";
    },
    setWorkArea(x, y, w, h) {
      if (!store.get("sysPos", null)) { sys.style.left = (x + 30) + "px"; sys.style.top = Math.max(y, y + h - 300) + "px"; }
      if (!store.get("menuPos", null)) { menu.style.left = (x + 110) + "px"; menu.style.top = Math.max(36, y + 8) + "px"; }
    },
    open(o) { if (!!o !== open) setOpen(!!o); },
    placeMenu(x, y) { menu.style.left = x + "px"; menu.style.top = y + "px"; store.set("menuPos", [x, y]); }
  };
})();
