import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Chart from "https://cdn.jsdelivr.net/npm/chart.js@4.4.3/auto/+esm";
import { SUPABASE_URL, SUPABASE_ANON_KEY } from "./config.js";

const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ── State ─────────────────────────────────────────────────────────────────────
const state = {
  people: [],            // [{id,name,color}]
  entries: [],           // [{id,person_id,entry_date,amazon,shopify,program,at_errors,hours_spent,daily_total,note}]
  selected: "team",      // person id or "team" — whose stats are highlighted (viewing)
  range: 90,             // 30 | 90 | "all"
  sessions: [],          // returns_timer_sessions rows (hours are derived from these)
  timer: { session: null, tick: null }, // the logged-in person's running session
  me: null,              // the logged-in person's returns_people row
  isAdmin: false,        // from me.is_admin (set by the invite, server-side)
};
const charts = {};

// ── Helpers ────────────────────────────────────────────────────────────────────
const $ = (s) => document.querySelector(s);
const pad = (n) => String(n).padStart(2, "0");
const todayISO = () => { const d = new Date(); return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`; };
const fmtDate = (iso) => { const [y,m,d] = iso.split("-"); return `${+m}/${+d}`; };
const fmtDateLong = (iso) => { const [y,m,d] = iso.split("-"); return new Date(y,m-1,d).toLocaleDateString(undefined,{month:"short",day:"numeric"}); };
const personById = (id) => state.people.find((p) => p.id === id);
const cssVar = (n) => getComputedStyle(document.documentElement).getPropertyValue(n).trim();
const total = (e) => e.amazon + e.shopify + e.program + e.at_errors;

function toast(msg) {
  const t = $("#toast"); t.textContent = msg; t.hidden = false;
  clearTimeout(toast._t); toast._t = setTimeout(() => (t.hidden = true), 2200);
}
function scopeEntries() {
  return state.selected === "team"
    ? state.entries
    : state.entries.filter((e) => e.person_id === state.selected);
}
function inRange(iso) {
  if (state.range === "all") return true;
  const d = new Date(iso + "T00:00:00");
  const cutoff = new Date(); cutoff.setDate(cutoff.getDate() - state.range);
  return d >= cutoff;
}

// ── Data load ───────────────────────────────────────────────────────────────────
async function loadAll() {
  const [{ data: people, error: pe }, { data: entries, error: ee }, { data: sessions }] = await Promise.all([
    sb.from("returns_people").select("*").order("name"),
    sb.from("returns_entries").select("*").order("entry_date"),
    sb.from("returns_timer_sessions").select("*"),
  ]);
  if (pe || ee) { toast("Load error"); console.error(pe || ee); return; }
  state.people = (people || []).filter((p) => p.active !== false);
  state.entries = (entries || []).map((e) => ({ ...e, daily_total: e.daily_total ?? total(e) }));
  state.sessions = sessions || [];
}

// Hours are DERIVED: the entry's stored hours_spent (historical / manual base)
// plus the duration of every completed timer session for that person + day.
function sessionHours(personId, date) {
  return state.sessions
    .filter((s) => s.person_id === personId && s.entry_date === date && s.ended_at)
    .reduce((a, s) => a + (new Date(s.ended_at) - new Date(s.started_at)) / 3600000, 0);
}
function hoursFor(e) { return (e.hours_spent || 0) + sessionHours(e.person_id, e.entry_date); }

// ── Person / range selectors ─────────────────────────────────────────────────────
function renderPersonSeg() {
  const seg = $("#personSeg");
  const opts = [{ id: "team", name: "Team", color: cssVar("--team") }, ...state.people];
  seg.innerHTML = opts.map((o) =>
    `<button role="tab" data-id="${o.id}" aria-selected="${state.selected === o.id}">
       ${o.id === "team" ? "👥 Team" : `<span class="swatch" style="background:${o.color}"></span>${o.name}`}
     </button>`).join("");
  seg.querySelectorAll("button").forEach((b) =>
    b.onclick = () => { state.selected = b.dataset.id; refreshAll(); });
}
function renderRangeSeg() {
  const seg = $("#rangeSeg");
  const opts = [[30,"30d"],[90,"90d"],["all","All"]];
  seg.innerHTML = opts.map(([v,l]) =>
    `<button role="tab" data-v="${v}" aria-selected="${String(state.range)===String(v)}">${l}</button>`).join("");
  seg.querySelectorAll("button").forEach((b) =>
    b.onclick = () => { state.range = b.dataset.v === "all" ? "all" : +b.dataset.v; renderRangeSeg(); renderCharts(); });
}

// ── Timer ────────────────────────────────────────────────────────────────────────
function fmtElapsed(ms) {
  const s = Math.floor(ms/1000); const h = Math.floor(s/3600), m = Math.floor((s%3600)/60), sec = s%60;
  return `${pad(h)}:${pad(m)}:${pad(sec)}`;
}
async function loadTimer() {
  stopTick();
  state.timer.session = null;
  const me = state.me;
  $("#timerBtn").disabled = !me;
  $("#timerFor").textContent = me ? `${me.name} — your timer` : "";
  if (!me) { renderTimerIdle(); return; }
  const { data } = await sb.from("returns_timer_sessions")
    .select("*").eq("person_id", me.id).is("ended_at", null)
    .order("started_at", { ascending: false }).limit(1);
  if (data && data.length) { state.timer.session = data[0]; startTick(); }
  else renderTimerIdle();
}
function renderTimerIdle() {
  $("#timerDisplay").textContent = "00:00:00";
  $("#timerDisplay").classList.remove("running");
  $("#timerBtn").textContent = "Start"; $("#timerBtn").classList.remove("stop");
}
function startTick() {
  const started = new Date(state.timer.session.started_at).getTime();
  const paint = () => { $("#timerDisplay").textContent = fmtElapsed(Date.now() - started); };
  paint(); $("#timerDisplay").classList.add("running");
  $("#timerBtn").textContent = "Stop"; $("#timerBtn").classList.add("stop");
  state.timer.tick = setInterval(paint, 1000);
}
function stopTick() { if (state.timer.tick) { clearInterval(state.timer.tick); state.timer.tick = null; } }

async function onTimerBtn() {
  const me = state.me; if (!me) return;
  if (!state.timer.session) {
    const { data, error } = await sb.from("returns_timer_sessions")
      .insert({ person_id: me.id, entry_date: todayISO() }).select().single();
    if (error) { console.error(error); return toast("Couldn’t start timer"); }
    state.timer.session = data; startTick(); toast("Timer started");
  } else {
    const started = new Date(state.timer.session.started_at).getTime();
    const mins = Math.round((Date.now() - started) / 60000);
    const { error } = await sb.from("returns_timer_sessions")
      .update({ ended_at: new Date().toISOString() }).eq("id", state.timer.session.id);
    if (error) { console.error(error); return toast("Couldn’t stop timer"); }
    state.timer.session = null; stopTick(); renderTimerIdle();
    await loadAll(); refreshExceptTimer();
    toast(`Logged ${mins} min to today`);
  }
}

// ── Today entry form ──────────────────────────────────────────────────────────────
// Admin (Karley) enters counts for any person / any date. Staff see their own day
// read-only (their timer banks the hours). The entry "target" differs by mode:
//   admin → the person+date pickers;  staff → the top-selected person + today.
function entryTarget() {
  if (state.isAdmin) {
    return { personId: $("#entryPerson").value || null, date: $("#entryDate").value || todayISO() };
  }
  return { personId: state.me?.id || null, date: todayISO() };  // staff = their own today, read-only
}
function fields() { return ["f_amazon","f_shopify","f_program","f_at","f_hours"]; }
function loadEntryForm() {
  const { personId, date } = entryTarget();
  const editable = state.isAdmin && !!personId;
  fields().forEach((id) => $("#"+id).disabled = !editable);
  $("#todayLabel").textContent = fmtDateLong(date);
  $("#entryHeading").firstChild.textContent = state.isAdmin ? "Log · " : "Today · ";

  if (!personId) {
    fields().forEach((id) => $("#"+id).value = "");
    $("#entryStatus").textContent = "";
    calcEntry(); return;
  }
  const e = state.entries.find((x) => x.person_id === personId && x.entry_date === date);
  $("#f_amazon").value  = e?.amazon    || "";
  $("#f_shopify").value = e?.shopify   || "";
  $("#f_program").value = e?.program   || "";
  $("#f_at").value      = e?.at_errors || "";
  // admin edits the manual "base" hours; staff see the derived total (base + timer) read-only
  const sess = sessionHours(personId, date);
  $("#f_hours").value = state.isAdmin ? (e?.hours_spent || "") : (((e?.hours_spent || 0) + sess) || "").toString();
  $("#entryStatus").textContent = state.isAdmin
    ? (e ? "Editing existing" : "New entry")
    : (sess ? "Karley enters counts · your timer logs hours" : "Karley enters counts · run your timer to log hours");
  calcEntry();
}
function calcEntry() {
  const a = +$("#f_amazon").value||0, s = +$("#f_shopify").value||0, p = +$("#f_program").value||0, at = +$("#f_at").value||0;
  const { personId, date } = entryTarget();
  // admin's Hours field is the base; add today's timer sessions for the true rate
  const h = (+$("#f_hours").value||0) + (state.isAdmin && personId ? sessionHours(personId, date) : 0);
  const t = a+s+p+at;
  $("#calcTotal").textContent = t;
  $("#calcAvg").textContent = h > 0 ? (t/h).toFixed(1) + " /hr" : "—";
}
async function saveEntry() {
  if (!state.isAdmin) return toast("Only the admin can enter counts");
  const { personId, date } = entryTarget();
  if (!personId) return toast("Choose a person");
  const row = {
    person_id: personId, entry_date: date,
    amazon: +$("#f_amazon").value||0, shopify: +$("#f_shopify").value||0,
    program: +$("#f_program").value||0, at_errors: +$("#f_at").value||0,
    hours_spent: +$("#f_hours").value||0,
  };
  const { error } = await sb.from("returns_entries").upsert(row, { onConflict: "person_id,entry_date" });
  if (error) { console.error(error); return toast("Save failed"); }
  await loadAll(); refreshExceptTimer(); toast("Saved");
}

// ── Auth: email invites (mirrors the Warehouse Hub) ─────────────────────────────────
function applyAdmin() { document.body.classList.toggle("admin", state.isAdmin); }
function setAuthStatus(msg, err) { const el = $("#authStatus"); el.textContent = msg || ""; el.classList.toggle("err", !!err); }
function showGate(msg, err) {
  $("#authGate").hidden = false;
  $("#userChip").hidden = true; $("#signOutBtn").hidden = true;
  if (msg !== undefined) setAuthStatus(msg, err);
}
function hideGate() { $("#authGate").hidden = true; }

// After auth: claim/create the profile server-side, then boot the app (or bounce).
async function route() {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) { state.me = null; state.isAdmin = false; applyAdmin(); showGate(""); return; }
  const { data: me, error } = await sb.rpc("returns_claim_profile");
  if (error) {
    if (/not invited/i.test(error.message)) {
      showGate(`Signed in as ${session.user.email}, but that email isn’t invited yet. Ask Karley to add you, then sign in again.`, true);
    } else { showGate(error.message, true); }
    return;
  }
  const person = Array.isArray(me) ? me[0] : me;
  state.me = person; state.isAdmin = !!person.is_admin;
  applyAdmin(); hideGate();
  $("#userChip").textContent = `${person.name}${person.is_admin ? " · admin" : ""}`;
  $("#userChip").hidden = false; $("#signOutBtn").hidden = false;
  await loadAll();
  renderEntryPickers();
  refreshAll();
  if (state.isAdmin) renderInvites();
}

sb.auth.onAuthStateChange(async (event) => {
  if (event === "PASSWORD_RECOVERY") {
    const np = prompt("Choose a new password (8+ characters):");
    if (np) { const { error } = await sb.auth.updateUser({ password: np }); toast(error ? error.message : "Password updated"); }
    route();                      // a recovery session is valid — go straight into the app
    return;
  }
  if (["SIGNED_IN", "SIGNED_OUT", "USER_UPDATED"].includes(event)) route();
});

async function doSignIn(email, password) {
  setAuthStatus("Signing in…");
  const timeout = new Promise((_, rej) => setTimeout(() => rej(new Error("timeout")), 9000));
  try {
    const { error } = await Promise.race([sb.auth.signInWithPassword({ email, password }), timeout]);
    if (error) setAuthStatus(error.message, true); else setAuthStatus("");
  } catch {
    setAuthStatus("Sign-in got stuck — tap “reset and retry” just below, then sign in again.", true);
  }
}
async function doSignUp(email, password) {
  if (!email || password.length < 8) return setAuthStatus("Enter your email and a password of at least 8 characters.", true);
  setAuthStatus("Creating your account…");
  const { data, error } = await sb.auth.signUp({ email, password });
  if (error) return setAuthStatus(error.message, true);
  if (!data.session) setAuthStatus("Account created — now sign in with those details.");
  // with email-confirmation off, SIGNED_IN fires and route() takes over.
}

// ── Invites (admin) ─────────────────────────────────────────────────────────────────
async function renderInvites() {
  const { data: invites } = await sb.from("returns_invited_emails").select("*").order("name");
  const linked = new Set(state.people.filter((p)=>p.email).map((p)=>p.email.toLowerCase()));
  $("#inviteList").innerHTML = (invites||[]).map((i) => `
    <li>
      <span>${i.name}<span class="em"> · ${i.email}</span>
        ${i.is_admin ? '<span class="badge">admin</span>' : ''}
        ${linked.has(i.email) ? '' : '<span class="badge pending">not signed in</span>'}
      </span>
      ${i.email === "karley@justforkix.com" ? "" : `<button class="row-del" data-email="${i.email}" title="Remove">✕</button>`}
    </li>`).join("") || `<li class="muted">No invites yet.</li>`;
  $("#inviteList").querySelectorAll(".row-del").forEach((b) => b.onclick = async () => {
    if (!confirm(`Remove invite for ${b.dataset.email}? They won’t be able to sign in.`)) return;
    await sb.from("returns_invited_emails").delete().eq("email", b.dataset.email);
    renderInvites();
  });
}
async function addInvite(name, email, isAdmin) {
  if (!name || !email) return toast("Name and email required");
  const { error } = await sb.from("returns_invited_emails")
    .insert({ name, email: email.toLowerCase(), is_admin: isAdmin });
  if (error) return toast(error.message);
  toast("Invited"); renderInvites();
}

function renderEntryPickers() {
  const sel = $("#entryPerson");
  const cur = sel.value;
  sel.innerHTML = state.people.map((p) => `<option value="${p.id}">${p.name}</option>`).join("");
  sel.value = cur || (state.selected !== "team" ? state.selected : state.people[0]?.id) || "";
  if (!$("#entryDate").value) $("#entryDate").value = todayISO();
}

// ── Goals (localStorage per person) ────────────────────────────────────────────────
function goalKey() { const p = personById(state.selected); return `returns_goal_${p ? p.name : "team"}`; }
function suggestedGoal(entries) {
  const timed = entries.filter((e) => hoursFor(e) > 0);
  const th = timed.reduce((a,e) => a + hoursFor(e), 0);
  const tt = timed.reduce((a,e) => a + e.daily_total, 0);
  const avg = th ? tt/th : 30;
  return Math.max(5, Math.ceil(avg / 5) * 5); // round up to nearest 5
}
function getGoal(entries) {
  const stored = localStorage.getItem(goalKey());
  return stored ? +stored : suggestedGoal(entries);
}

// ── Stat tiles ────────────────────────────────────────────────────────────────────
function renderTiles() {
  const scope = scopeEntries();
  const timed = scope.filter((e) => hoursFor(e) > 0);
  const th = timed.reduce((a,e) => a + hoursFor(e), 0);
  const tt = timed.reduce((a,e) => a + e.daily_total, 0);
  const avg = th ? tt/th : null;
  const inR = scope.filter((e) => inRange(e.entry_date));
  const periodTotal = inR.reduce((a,e) => a + e.daily_total, 0);
  const best = scope.reduce((b,e) => e.daily_total > (b?.daily_total ?? -1) ? e : b, null);
  const goal = getGoal(scope);
  $("#goalInput").value = goal;

  let goalTile;
  if (avg == null) {
    goalTile = `<div class="tile"><div class="k">Goal</div><div class="v">${goal}<small>/hr</small></div>
      <div class="sub">Log hours with the timer to track progress</div></div>`;
  } else {
    const diff = avg - goal;
    const hit = diff >= 0;
    goalTile = `<div class="tile"><div class="k">Goal · ${goal}/hr</div>
      <div class="v" style="color:${hit ? "var(--good)" : "var(--ink)"}">${avg.toFixed(1)}<small>/hr now</small></div>
      <div class="sub">${hit ? "🎉 Beating goal by " + diff.toFixed(1) : (goal-avg).toFixed(1) + " to go — you got this"}</div></div>`;
  }

  const rangeLabel = state.range === "all" ? "all time" : `last ${state.range}d`;
  $("#tiles").innerHTML = `
    <div class="tile"><div class="k">Avg speed ${state.selected==="team"?"(team)":""}</div>
      <div class="v">${avg == null ? "—" : avg.toFixed(1)}<small>/hr</small></div>
      <div class="sub">across ${timed.length} timed day${timed.length===1?"":"s"}</div></div>
    <div class="tile"><div class="k">Refunds · ${rangeLabel}</div>
      <div class="v">${periodTotal.toLocaleString()}</div>
      <div class="sub">${inR.length} day${inR.length===1?"":"s"} logged</div></div>
    <div class="tile"><div class="k">Best day</div>
      <div class="v">${best ? best.daily_total : "—"}</div>
      <div class="sub">${best ? fmtDateLong(best.entry_date) + (state.selected==="team" ? " · "+(personById(best.person_id)?.name||"") : "") : "—"}</div></div>
    ${goalTile}`;
}

// ── Charts ────────────────────────────────────────────────────────────────────────
function baseOpts() {
  const ink = cssVar("--ink-2"), grid = cssVar("--grid"), muted = cssVar("--muted");
  return {
    responsive: true, maintainAspectRatio: false,
    interaction: { mode: "index", intersect: false },
    plugins: {
      legend: { labels: { color: ink, boxWidth: 10, boxHeight: 10, usePointStyle: true, font: { size: 12 } } },
      tooltip: { backgroundColor: cssVar("--ink"), titleColor: cssVar("--surface-1"),
                 bodyColor: cssVar("--surface-1"), padding: 10, cornerRadius: 8, boxPadding: 4 },
    },
    scales: {
      x: { grid: { color: grid, drawTicks: false }, ticks: { color: muted, font: { size: 11 }, maxRotation: 0, autoSkipPadding: 16 }, border: { display: false } },
      y: { grid: { color: grid, drawTicks: false }, ticks: { color: muted, font: { size: 11 } }, border: { display: false }, beginAtZero: true },
    },
  };
}
function seriesForPerson(p) { return p.name === "Karley" ? cssVar("--series-1") : p.name === "Riley" ? cssVar("--series-2") : cssVar("--team"); }

function renderCharts() {
  Object.values(charts).forEach((c) => c && c.destroy());
  const dates = [...new Set(state.entries.filter((e)=>inRange(e.entry_date)).map((e)=>e.entry_date))].sort();
  const labels = dates.map(fmtDate);

  // 1 · Daily total — one line per person (always both, for comparison)
  charts.totals = new Chart($("#chartTotals"), {
    type: "line",
    data: { labels, datasets: state.people.map((p) => {
      const byDate = Object.fromEntries(state.entries.filter((e)=>e.person_id===p.id).map((e)=>[e.entry_date, e.daily_total]));
      const c = seriesForPerson(p);
      return { label: p.name, data: dates.map((d)=> byDate[d] ?? null), borderColor: c, backgroundColor: c,
               borderWidth: 2, pointRadius: 2, pointHoverRadius: 5, tension: .25, spanGaps: true };
    }) },
    options: baseOpts(),
  });

  // 2 · Speed (avg/hr) on timed days + goal line for selected
  const goal = getGoal(scopeEntries());
  const speedOpts = baseOpts();
  speedOpts.plugins.annotationGoal = goal;
  charts.speed = new Chart($("#chartSpeed"), {
    type: "line",
    data: { labels, datasets: [
      ...state.people.map((p) => {
        const byDate = Object.fromEntries(state.entries.filter((e)=>e.person_id===p.id && hoursFor(e)>0)
          .map((e)=>[e.entry_date, +(e.daily_total/hoursFor(e)).toFixed(1)]));
        const c = seriesForPerson(p);
        return { label: p.name, data: dates.map((d)=> byDate[d] ?? null), borderColor: c, backgroundColor: c,
                 borderWidth: 2, pointRadius: 3, pointHoverRadius: 5, tension: .25, spanGaps: true };
      }),
      { label: `Goal (${goal})`, data: dates.map(()=>goal), borderColor: cssVar("--muted"),
        borderDash: [6,5], borderWidth: 1.5, pointRadius: 0, fill: false },
    ] },
    options: speedOpts,
  });

  // 3 · Channel mix — stacked bar per person over the range
  const channels = [["amazon","Amazon","#2a78d6"],["shopify","Shopify","#1baf7a"],["program","Program","#eda100"],["at_errors","AT Errors","#eb6834"]];
  const ppl = state.people;
  charts.mix = new Chart($("#chartMix"), {
    type: "bar",
    data: { labels: ppl.map((p)=>p.name), datasets: channels.map(([key,label,color]) => ({
      label, backgroundColor: color, borderColor: cssVar("--surface-1"), borderWidth: 2, borderRadius: 3,
      data: ppl.map((p)=> state.entries.filter((e)=>e.person_id===p.id && inRange(e.entry_date)).reduce((a,e)=>a+e[key],0)),
    })) },
    options: { ...baseOpts(), scales: {
      x: { ...baseOpts().scales.x, stacked: true },
      y: { ...baseOpts().scales.y, stacked: true },
    } },
  });
}

// ── Recent entries table ────────────────────────────────────────────────────────────
function renderTable() {
  const rows = scopeEntries().filter((e)=>inRange(e.entry_date))
    .sort((a,b)=> b.entry_date.localeCompare(a.entry_date) || a.person_id.localeCompare(b.person_id))
    .slice(0, 40);
  const tb = $("#entriesTable tbody");
  tb.innerHTML = rows.map((e) => {
    const p = personById(e.person_id);
    const h = hoursFor(e);
    const avg = h > 0 ? (e.daily_total/h).toFixed(1) : "—";
    return `<tr>
      <td>${fmtDate(e.entry_date)}${e.note ? `<span class="note-badge" title="${e.note}">range</span>` : ""}</td>
      <td><span class="swatch" style="display:inline-block;width:8px;height:8px;border-radius:50%;background:${seriesForPerson(p)};margin-right:6px"></span>${p?.name||"?"}</td>
      <td class="num">${e.amazon||""}</td><td class="num">${e.shopify||""}</td>
      <td class="num">${e.program||""}</td><td class="num">${e.at_errors||""}</td>
      <td class="num"><strong>${e.daily_total}</strong></td>
      <td class="num">${h ? h.toFixed(2) : "—"}</td><td class="num">${avg}</td>
      <td><button class="row-del admin-only" data-id="${e.id}" title="Delete">✕</button></td>
    </tr>`;
  }).join("") || `<tr><td colspan="10" class="muted" style="text-align:center;padding:24px">No entries in this range.</td></tr>`;
  tb.querySelectorAll(".row-del").forEach((b) => b.onclick = async () => {
    if (!state.isAdmin) return;
    if (!confirm("Delete this entry?")) return;
    await sb.from("returns_entries").delete().eq("id", b.dataset.id);
    await loadAll(); refreshExceptTimer(); toast("Deleted");
  });
}

// ── Refresh orchestration ─────────────────────────────────────────────────────────
function refreshExceptTimer() { renderTiles(); renderCharts(); renderTable(); loadEntryForm(); }
function refreshAll() { renderPersonSeg(); refreshExceptTimer(); loadTimer(); }

// ── Theme ────────────────────────────────────────────────────────────────────────
function initTheme() {
  const saved = localStorage.getItem("returns_theme");
  if (saved) document.documentElement.setAttribute("data-theme", saved);
  $("#themeBtn").onclick = () => {
    const cur = document.documentElement.getAttribute("data-theme")
      || (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
    const next = cur === "dark" ? "light" : "dark";
    document.documentElement.setAttribute("data-theme", next);
    localStorage.setItem("returns_theme", next);
    renderCharts();
  };
}

// ── Wire up ────────────────────────────────────────────────────────────────────────
function wire() {
  fields().forEach((id)=> $("#"+id).addEventListener("input", calcEntry));
  $("#saveBtn").onclick = saveEntry;
  $("#timerBtn").onclick = onTimerBtn;
  $("#entryPerson").addEventListener("change", loadEntryForm);
  $("#entryDate").addEventListener("change", loadEntryForm);
  $("#goalInput").addEventListener("change", () => {
    localStorage.setItem(goalKey(), String(+$("#goalInput").value || 0));
    renderTiles(); renderCharts();
  });
  // ── auth ──
  let mode = "in";
  $("#authForm").addEventListener("submit", (e) => {
    e.preventDefault();
    const email = $("#authEmail").value.trim(), pw = $("#authPassword").value;
    (mode === "in" ? doSignIn : doSignUp)(email, pw);
  });
  $("#authToggle").onclick = () => {
    mode = mode === "in" ? "up" : "in";
    $("#authSubmit").textContent = mode === "in" ? "Sign in" : "Create account";
    $("#authMode").textContent = mode === "in" ? "Sign in to your JFK account." : "Create your account with your invited email.";
    $("#authToggle").textContent = mode === "in" ? "New here? Create your account" : "Already have an account? Sign in";
    $("#authPassword").autocomplete = mode === "in" ? "current-password" : "new-password";
    setAuthStatus("");
  };
  $("#authForgot").onclick = async () => {
    const email = $("#authEmail").value.trim();
    if (!email) return setAuthStatus("Type your email above first.", true);
    const { error } = await sb.auth.resetPasswordForEmail(email, { redirectTo: location.origin + location.pathname });
    setAuthStatus(error ? error.message : "Reset link sent — check your email.", !!error);
  };
  $("#signOutBtn").onclick = () => sb.auth.signOut();
  $("#authReset").onclick = async () => {
    setAuthStatus("Resetting…");
    try { await sb.auth.signOut({ scope: "local" }); } catch {}
    try { Object.keys(localStorage).filter((k) => k.startsWith("sb-")).forEach((k) => localStorage.removeItem(k)); } catch {}
    location.replace(location.origin + location.pathname);   // clean URL drops any leftover #recovery hash
  };
  // ── invites ──
  $("#invitesBtn").onclick = () => { renderInvites(); $("#invitesModal").hidden = false; };
  $("#invitesClose").onclick = () => { $("#invitesModal").hidden = true; };
  $("#invitesModal").addEventListener("click", (e) => { if (e.target.id === "invitesModal") $("#invitesModal").hidden = true; });
  $("#inviteForm").addEventListener("submit", (e) => {
    e.preventDefault();
    addInvite($("#inviteName").value.trim(), $("#inviteEmail").value.trim(), $("#inviteAdmin").checked);
    e.target.reset();
  });
}

// ── Boot ────────────────────────────────────────────────────────────────────────
(async function boot() {
  initTheme(); wire(); renderRangeSeg();
  showGate("");        // cover the app until we know who's signed in
  await route();       // session? → claim + load; otherwise the gate stays up
})();
