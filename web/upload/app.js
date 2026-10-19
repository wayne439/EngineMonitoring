// Engine Pulse upload page. Uses the same Supabase project as the iPad app:
// files go to the private "engine-logs" bucket under <user id>/inbox/ and a row in inbox_uploads,
// which the app picks up the next time it opens.
(function () {
  "use strict";

  const BUCKET = "engine-logs";
  const CHECKLIST = [
    { id: "logs", title: "Engine monitor log files", level: "Required",
      detail: "The CSV files from your avionics data card (data_log folder). The last 20 or more flights give the best baseline.",
      accept: ".csv,.jpi,.dat,text/csv" },
    { id: "poh-limits", title: "Your POH / AFM (the whole PDF)", level: "Required",
      detail: "Including the Section 9 supplements. The engine model, all engine limits and any turbo limits are read from it.",
      accept: ".pdf" },
    { id: "logbook", title: "Last annual and last oil change", level: "Required",
      detail: "Logbook entries (date and tach / total time), or record them in the app under MAINTENANCE. Add your AD compliance record if you have one.",
      accept: ".pdf,image/*" },
    { id: "engine-time", title: "Engine total time", level: "Recommended",
      detail: "The latest engine logbook entry showing total time (and the overhaul entry, if it has been overhauled).", accept: ".pdf,image/*" },
    { id: "turbo", title: "Turbo supplement (only if it isn't in your POH)", level: "Optional",
      detail: "Only needed when your POH doesn't include the turbo or turbonormalizer limits. The app tells you if it's missing.", accept: ".pdf,image/*" },
    { id: "oil-analysis", title: "Oil analysis reports", level: "Optional",
      detail: "Your lab reports, if you use oil analysis.", accept: ".pdf,image/*" },
    { id: "squawks", title: "Open squawks and recent engine work", level: "Optional",
      detail: "Anything your A&P is watching, or work since the last annual.", accept: ".pdf,image/*,.txt" },
    { id: "other", title: "Anything else", level: "Optional", detail: "", accept: "" },
  ];
  const STATUS = {
    received: "waiting for the app", imported: "added as a flight", stored: "saved",
    unsupported: "saved; analysis coming", failed: "could not be read", processing: "processing",
  };

  const $ = (id) => document.getElementById(id);
  const cfg = window.EM_CONFIG || {};
  if (!cfg.supabaseUrl || !cfg.supabaseAnonKey || !window.supabase) {
    $("not-configured").classList.remove("hidden");
    return;
  }
  const sb = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey);
  let registering = false;
  let user = null;
  let aircraftId = null;
  let uploads = [];
  const notes = {}; // per-checklist-item status line, kept across re-renders

  function note(category, text, kind) {
    notes[category] = { text, kind };
    const el = document.querySelector('[data-cat="' + category + '"] .msg');
    if (el) msg(el, text, kind);
  }

  // ---------- helpers
  function msg(el, text, kind) {
    el.textContent = text || "";
    el.className = "msg " + (kind || "");
  }
  function safeName(name) { return name.replace(/[^A-Za-z0-9._-]/g, "_"); }
  function formatOf(name) {
    const ext = name.split(".").pop().toLowerCase();
    if (ext === "csv") return "garmin-csv";
    if (ext === "jpi") return "jpi";
    if (ext === "pdf") return "pdf";
    if (["jpg", "jpeg", "png", "heic"].includes(ext)) return "image";
    return "unknown";
  }
  function when(ts) { return ts ? new Date(ts).toLocaleString() : ""; }
  function li(text, right) {
    const el = document.createElement("li");
    const a = document.createElement("span"); a.textContent = text;
    const b = document.createElement("span"); b.className = "muted"; b.textContent = right || "";
    el.append(a, b);
    return el;
  }

  // ---------- auth
  function setMode(reg) {
    registering = reg;
    $("auth-title").textContent = reg ? "Register for Engine Pulse" : "Log in";
    $("auth-submit").textContent = reg ? "Register" : "Log in";
    $("toggle-mode").textContent = reg ? "Already registered? Log in" : "New here? Register";
    $("name-field").classList.toggle("hidden", !reg);
    $("password").autocomplete = reg ? "new-password" : "current-password";
    msg($("auth-msg"), "");
  }
  $("toggle-mode").addEventListener("click", () => setMode(!registering));

  $("auth-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    const email = $("email").value.trim();
    const password = $("password").value;
    const out = $("auth-msg");
    msg(out, registering ? "Creating your account…" : "Signing in…");
    if (registering) {
      const { data, error } = await sb.auth.signUp({ email, password, options: { data: { full_name: $("name").value.trim() } } });
      if (error) return msg(out, error.message, "err");
      if (!data.session) return msg(out, "Account created. Check " + email + " for a confirmation link, then log in.", "ok");
    } else {
      const { error } = await sb.auth.signInWithPassword({ email, password });
      if (error) return msg(out, error.message, "err");
    }
  });

  $("forgot").addEventListener("click", async () => {
    const email = $("email").value.trim();
    const out = $("auth-msg");
    if (!email.includes("@")) return msg(out, "Enter your email first.", "err");
    const { error } = await sb.auth.resetPasswordForEmail(email, { redirectTo: location.href });
    msg(out, error ? error.message : "If an account exists for " + email + ", a reset link is on its way.", error ? "err" : "ok");
  });

  $("signout").addEventListener("click", () => sb.auth.signOut());

  sb.auth.onAuthStateChange(async (event, session) => {
    if (event === "PASSWORD_RECOVERY") {
      const pw = prompt("Choose a new password (8 or more characters):");
      if (pw && pw.length >= 8) {
        const { error } = await sb.auth.updateUser({ password: pw });
        alert(error ? error.message : "Password updated.");
      }
    }
    user = session ? session.user : null;
    $("auth").classList.toggle("hidden", !!user);
    $("app").classList.toggle("hidden", !user);
    if (user) await loadAll();
  });

  // ---------- data
  async function loadAll() {
    const name = (user.user_metadata && user.user_metadata.full_name) || user.email;
    $("hello").textContent = "Welcome, " + name;
    const { data: planes, error } = await sb.from("aircraft").select("id, tail_number, make, model").order("updated_at", { ascending: false });
    if (error) { $("aircraft-line").textContent = error.message; return; }
    const pick = $("aircraft");
    pick.innerHTML = "";
    (planes || []).forEach((p) => {
      const o = document.createElement("option");
      o.value = p.id;
      o.textContent = [p.tail_number, [p.make, p.model].filter(Boolean).join(" ")].filter(Boolean).join(" – ") || "Unnamed aircraft";
      pick.append(o);
    });
    aircraftId = planes && planes.length ? planes[0].id : null;
    $("aircraft-pick").classList.toggle("hidden", !planes || planes.length < 2);
    pick.onchange = () => { aircraftId = pick.value; };
    const noPlane = $("no-aircraft");
    if (!aircraftId) {
      noPlane.textContent = "No aircraft yet. Set it up in the iPad app (Register or AIRCRAFT > Aircraft Profile); you can still upload now.";
      noPlane.classList.remove("hidden");
      $("aircraft-line").textContent = "";
    } else {
      noPlane.classList.add("hidden");
      $("aircraft-line").textContent = pick.options[0].textContent;
    }
    await loadUploads();
  }

  async function loadUploads() {
    const { data, error } = await sb.from("inbox_uploads")
      .select("id, category, original_filename, status, received_at")
      .order("received_at", { ascending: false });
    uploads = error ? [] : data || [];
    renderChecklist();
    const all = $("all-files");
    all.innerHTML = "";
    if (!uploads.length) all.append(li("Nothing uploaded yet."));
    uploads.forEach((u) => all.append(li(u.original_filename, (STATUS[u.status] || u.status) + " · " + when(u.received_at))));
  }

  async function upload(category, files) {
    let done = 0;
    for (const file of files) {
      note(category, "Uploading " + file.name + "…");
      const path = user.id + "/inbox/" + Date.now() + "-" + safeName(file.name);
      const up = await sb.storage.from(BUCKET).upload(path, file, { upsert: true, contentType: file.type || "application/octet-stream" });
      if (up.error) { note(category, file.name + ": " + up.error.message, "err"); continue; }
      const row = {
        aircraft_id: aircraftId, source: "web", category, original_filename: file.name, storage_path: path,
        size_bytes: file.size, format: formatOf(file.name), status: "received",
      };
      const ins = await sb.from("inbox_uploads").insert(row);
      if (ins.error) { note(category, file.name + ": " + ins.error.message, "err"); continue; }
      done += 1;
    }
    if (done) note(category, done + " file" + (done === 1 ? "" : "s") + " uploaded. Open the app to bring them in.", "ok");
    await loadUploads();
  }

  // ---------- checklist
  function renderChecklist() {
    const root = $("checklist");
    root.innerHTML = "";
    CHECKLIST.forEach((item) => {
      const mine = uploads.filter((u) => u.category === item.id);
      const card = document.createElement("div");
      card.className = "item";
      card.dataset.cat = item.id;
      const head = document.createElement("div");
      head.className = "item-head";
      const title = document.createElement("strong");
      title.textContent = (mine.length ? "✓ " : "") + item.title;
      const tag = document.createElement("span");
      tag.className = "tag" + (item.level === "Required" ? " req" : "");
      tag.textContent = item.level.toUpperCase();
      head.append(title, tag);
      card.append(head);
      if (item.detail) {
        const d = document.createElement("div");
        d.className = "muted"; d.style.fontSize = ".9rem"; d.textContent = item.detail;
        card.append(d);
      }
      const input = document.createElement("input");
      input.type = "file"; input.multiple = true; input.className = "hidden";
      if (item.accept) input.accept = item.accept;
      input.addEventListener("change", () => { if (input.files.length) upload(item.id, Array.from(input.files)); });
      const drop = document.createElement("div");
      drop.className = "drop";
      drop.textContent = "Drop files here or click to choose";
      drop.addEventListener("click", () => input.click());
      drop.addEventListener("dragover", (e) => { e.preventDefault(); drop.classList.add("over"); });
      drop.addEventListener("dragleave", () => drop.classList.remove("over"));
      drop.addEventListener("drop", (e) => {
        e.preventDefault(); drop.classList.remove("over");
        if (e.dataTransfer.files.length) upload(item.id, Array.from(e.dataTransfer.files));
      });
      const status = document.createElement("div");
      status.className = "msg";
      if (notes[item.id]) msg(status, notes[item.id].text, notes[item.id].kind);
      const list = document.createElement("ul");
      list.className = "files";
      mine.slice(0, 8).forEach((u) => list.append(li(u.original_filename, STATUS[u.status] || u.status)));
      card.append(input, drop, status, list);
      root.append(card);
    });
  }

  setMode(false);
  $("auth").classList.remove("hidden");
})();
