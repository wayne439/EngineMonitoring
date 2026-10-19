// Engine Pulse web sign-up. Creates the same Supabase account the app uses (email + password,
// confirmed with the 6-digit code in the "Confirm signup" email) and records the pilot's beta request
// (tail number, aircraft, avionics, devices) in the account's user metadata, where it shows in
// Supabase > Authentication > Users. No new tables: the app reads its own data from the aircraft table.
(function () {
  "use strict";

  const SUPPORTED_TODAY = ["Cirrus Perspective", "Cirrus Perspective+", "Garmin G1000", "Garmin G1000 NXi"];
  const TERMS_VERSION = "2026-10-19";
  const $ = (id) => document.getElementById(id);
  const cfg = window.EM_CONFIG || {};

  const steps = { account: $("step-account"), code: $("step-code"), done: $("step-done") };
  function show(name) {
    Object.entries(steps).forEach(([k, el]) => { el.hidden = k !== name; });
    const first = steps[name].querySelector("input, button, a");
    if (first && name !== "account") first.focus();
    window.scrollTo({ top: 0, behavior: "smooth" });
  }
  function say(el, text, kind) {
    el.textContent = text || "";
    el.className = "form-msg" + (kind ? " " + kind : "");
  }
  function busy(btn, on, label) {
    btn.disabled = on;
    if (label) btn.textContent = label;
  }

  if (!cfg.supabaseUrl || !cfg.supabaseAnonKey || !window.supabase) {
    $("not-configured").hidden = false;
    steps.account.hidden = true;
    return;
  }
  const sb = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey);
  let email = "";
  let fullName = "";

  // Avionics: show a note for monitors that aren't read yet, and a free-text box for "Other".
  $("avionics").addEventListener("change", () => {
    const v = $("avionics").value;
    $("other-field").hidden = v !== "Other";
    const note = $("avionics-note");
    if (v && !SUPPORTED_TODAY.includes(v)) {
      note.hidden = false;
      note.textContent = "Engine Pulse reads Perspective, Perspective+, G1000 and G1000 NXi logs today. Support for "
        + (v === "Other" ? "other monitors" : v) + " is coming, and we'll still add you to the list.";
    } else {
      note.hidden = true;
    }
  });
  $("tail").addEventListener("input", (e) => { e.target.value = e.target.value.toUpperCase().replace(/\s+/g, ""); });

  // Step 1: create the account.
  steps.account.addEventListener("submit", async (e) => {
    e.preventDefault();
    const out = $("account-msg");
    const btn = $("create");
    fullName = $("name").value.trim();
    email = $("email").value.trim().toLowerCase();
    const password = $("password").value;
    const tail = $("tail").value.trim();
    let avionics = $("avionics").value;
    if (avionics === "Other") avionics = $("other").value.trim() ? "Other: " + $("other").value.trim() : "Other";
    const devices = Array.from(document.querySelectorAll('input[name="device"]:checked')).map((c) => c.value);

    if (!fullName) return say(out, "Please enter your name.", "err");
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return say(out, "Please enter a valid email address.", "err");
    if (password.length < 8) return say(out, "Your password needs 8 or more characters.", "err");
    if (!tail) return say(out, "Please enter your tail number.", "err");
    if (!avionics) return say(out, "Please choose your avionics.", "err");
    if (!$("consent").checked) return say(out, "Please agree to the Terms of Use and Privacy Policy.", "err");

    busy(btn, true, "Creating your account…");
    say(out, "");
    const { data, error } = await sb.auth.signUp({
      email, password,
      options: {
        emailRedirectTo: new URL("../upload/", location.href).href,
        data: {
          full_name: fullName,
          beta_request: true,
          signup_source: "web",
          tail_number: tail,
          aircraft: $("aircraft").value.trim(),
          avionics,
          devices: devices.join(", "),
          terms_version: TERMS_VERSION,
          terms_accepted_at: new Date().toISOString(),
        },
      },
    });
    busy(btn, false, "Create account");

    if (error) {
      const m = (error.message || "").toLowerCase();
      if (m.includes("already registered") || m.includes("already exists")) return alreadyRegistered(out);
      if (m.includes("rate limit")) return say(out, "Too many sign-ups in a short time. Please try again in a few minutes, or email sales@enginepulse.net.", "err");
      return say(out, error.message, "err");
    }
    // Supabase hides whether an email is taken: an existing, confirmed account comes back with no identities.
    if (data.user && Array.isArray(data.user.identities) && data.user.identities.length === 0) return alreadyRegistered(out);
    if (data.session) return finish(); // email confirmation is switched off in Supabase
    $("code-email").textContent = email;
    show("code");
  });

  function alreadyRegistered(out) {
    out.innerHTML = "";
    out.className = "form-msg err";
    out.append("There's already an account for this email. ");
    const a = document.createElement("a");
    a.href = "../upload/";
    a.textContent = "Sign in on the upload page";
    out.append(a, " or use Forgot password there.");
  }

  // Step 2: confirm with the 6-digit code (same check the app uses).
  steps.code.addEventListener("submit", async (e) => {
    e.preventDefault();
    const out = $("code-msg");
    const btn = $("verify");
    const token = $("code").value.replace(/\D/g, "");
    if (token.length < 6) return say(out, "Enter the 6-digit code from the email.", "err");
    busy(btn, true, "Checking…");
    const { error } = await sb.auth.verifyOtp({ email, token, type: "email" });
    busy(btn, false, "Confirm email");
    if (error) {
      const m = (error.message || "").toLowerCase();
      return say(out, m.includes("expired") || m.includes("invalid")
        ? "That code didn't work or has expired. Check the newest email, or send a new code."
        : error.message, "err");
    }
    finish();
  });

  $("resend").addEventListener("click", async () => {
    const out = $("code-msg");
    const { error } = await sb.auth.resend({ type: "signup", email, options: { emailRedirectTo: new URL("../upload/", location.href).href } });
    say(out, error ? error.message : "A new code is on its way to " + email + ". Use the newest one.", error ? "err" : "ok");
  });
  $("restart").addEventListener("click", () => { say($("code-msg"), ""); $("code").value = ""; show("account"); $("email").focus(); });

  function finish() {
    $("done-email").textContent = email;
    $("done-name").textContent = fullName ? ", " + fullName.split(" ")[0] : "";
    show("done");
  }
})();
