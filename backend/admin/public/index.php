<?php
declare(strict_types=1);
$apiBase = 'https://api.progressquest.me/api/v1';
?><!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>PQ Multiplayer Admin</title>
  <style>
    :root {
      --bg: #f3f5f9;
      --card: #ffffff;
      --ink: #121722;
      --muted: #697285;
      --border: #d8deea;
      --accent: #1e4ed8;
      --ok: #0f8a36;
      --err: #ba1b1b;
    }
    * { box-sizing: border-box; }
    body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: var(--bg); color: var(--ink); }
    header { display:flex; justify-content:space-between; align-items:center; gap:12px; padding:14px 18px; background:#121722; color:#fff; }
    main { max-width: 1560px; margin: 0 auto; padding: 16px; display:grid; gap:12px; }
    .hidden { display:none !important; }
    .row { display:grid; grid-template-columns: repeat(12, 1fr); gap:12px; }
    .card { background:var(--card); border:1px solid var(--border); border-radius:12px; padding:12px; }
    .span-12 { grid-column: span 12; }
    .span-8 { grid-column: span 8; }
    .span-6 { grid-column: span 6; }
    .span-4 { grid-column: span 4; }
    @media (max-width: 1200px) { .span-8, .span-6, .span-4 { grid-column: span 12; } }
    h2 { margin:0 0 8px; font-size:16px; }
    h3 { margin:0 0 6px; font-size:14px; }
    .muted { color: var(--muted); font-size: 13px; }
    .status { min-height: 18px; font-size: 13px; margin-top: 8px; }
    .ok { color: var(--ok); }
    .err { color: var(--err); }
    .toolbar { display:flex; flex-wrap:wrap; gap:8px; align-items:flex-end; }
    label { font-size: 12px; color: var(--muted); display:flex; flex-direction:column; gap:4px; }
    input, select, button { font: inherit; }
    input, select { border:1px solid #c8cfdd; background:#fff; border-radius:8px; padding:7px 8px; min-width: 130px; }
    button { border:1px solid #c8cfdd; border-radius:8px; background:#fff; padding:7px 10px; cursor:pointer; }
    button.primary { background: var(--accent); color:#fff; border-color:var(--accent); }
    button.ghost { border-color: transparent; color: var(--accent); background: transparent; padding: 0; }
    button:disabled { opacity:.5; cursor:not-allowed; }
    .table-wrap { max-height: 320px; overflow:auto; border:1px solid var(--border); border-radius:10px; }
    table { width:100%; border-collapse: collapse; font-size:13px; }
    th, td { text-align:left; border-bottom:1px solid #eef1f6; padding:8px 6px; vertical-align: top; }
    th { position: sticky; top: 0; background: #f8faff; z-index: 1; }
    .chip { display:inline-block; padding:2px 8px; border-radius:999px; font-size:11px; border:1px solid var(--border); background:#f8faff; }
    .chip.ok { border-color:#bde2c7; background:#edf9f0; color:#0f8a36; }
    .chip.err { border-color:#efb8b8; background:#fff0f0; color:#ba1b1b; }
    .stack { display:flex; flex-direction:column; gap:8px; }
    .split { display:grid; grid-template-columns: 1fr 1fr; gap:10px; }
    @media (max-width:900px) { .split { grid-template-columns: 1fr; } }
  </style>
</head>
<body>
<header>
  <div>
    <strong>PQ Multiplayer Admin</strong>
    <div class="muted">API: <code id="apiBaseLabel"></code></div>
  </div>
  <div id="sessionBadge" class="muted">Not logged in</div>
</header>

<main>
  <section id="loginCard" class="card span-12">
    <h2>Admin Login</h2>
    <div class="toolbar">
      <label>Username<input id="loginUser" autocomplete="username"></label>
      <label>Password<input id="loginPass" type="password" autocomplete="current-password"></label>
      <button id="loginBtn" class="primary">Login</button>
    </div>
    <div id="loginStatus" class="status"></div>
  </section>

  <section id="adminPanel" class="hidden">
    <div class="row">
      <div class="card span-8" id="accountsCard">
        <h2>Accounts</h2>
        <div class="toolbar">
          <label>Search<input id="accountSearch" placeholder="email or public name"></label>
          <button id="refreshAccountsBtn">Refresh</button>
          <button id="clearAccountFilterBtn">Clear Filter</button>
        </div>
        <div class="table-wrap" style="margin-top:8px;">
          <table>
            <thead>
              <tr><th>Email</th><th>Public Name</th><th>Verified</th><th>Actions</th></tr>
            </thead>
            <tbody id="accountsBody"></tbody>
          </table>
        </div>
        <div id="accountsStatus" class="status"></div>
      </div>

      <div class="card span-4" id="realmsCard">
        <h2>Realms</h2>
        <div class="toolbar">
          <label>Realm ID<input id="realmId" value="realm_goobland_1"></label>
          <label>Name<input id="realmName" value="Goobland"></label>
          <label>Status
            <select id="realmStatus">
              <option value="active">active</option>
              <option value="coming_soon">coming_soon</option>
              <option value="disabled">disabled</option>
            </select>
          </label>
          <button id="createRealmBtn" class="primary">Create Realm</button>
          <button id="refreshRealmsBtn">Refresh</button>
        </div>
        <div class="table-wrap" style="max-height:210px; margin-top:8px;">
          <table>
            <thead><tr><th>ID</th><th>Name</th><th>Status</th><th>Guilds</th></tr></thead>
            <tbody id="realmsBody"></tbody>
          </table>
        </div>
        <div id="realmsStatus" class="status"></div>
      </div>

      <div class="card span-6" id="charactersCard">
        <h2>Characters</h2>
        <div class="toolbar">
          <label>Search<input id="characterSearch" placeholder="character/account"></label>
          <label>Account Filter<input id="characterAccountFilter" placeholder="accountId"></label>
          <button id="refreshCharactersBtn">Refresh</button>
          <button id="clearCharacterFilterBtn">Clear</button>
        </div>
        <div class="table-wrap" style="margin-top:8px;">
          <table>
            <thead>
              <tr><th>Name</th><th>Mode</th><th>Owner</th><th>Actions</th></tr>
            </thead>
            <tbody id="charactersBody"></tbody>
          </table>
        </div>
        <div id="charactersStatus" class="status"></div>
      </div>

      <div class="card span-6" id="guildsCard">
        <h2>Guilds</h2>
        <div class="toolbar">
          <label>Search<input id="guildSearch" placeholder="guild/tag/alignment/type"></label>
          <button id="refreshGuildsBtn">Refresh</button>
        </div>
        <div class="table-wrap" style="margin-top:8px;">
          <table>
            <thead>
              <tr><th>Guild</th><th>Status</th><th>Alignment</th><th>Type</th><th>Members</th><th>Actions</th></tr>
            </thead>
            <tbody id="guildsBody"></tbody>
          </table>
        </div>
        <div id="guildsStatus" class="status"></div>
      </div>

      <div class="card span-6" id="alignmentCard">
        <h2>Config: Alignment</h2>
        <div class="split">
          <div class="stack">
            <h3>Add Alignment</h3>
            <div class="toolbar">
              <label>Code<input id="alignmentCode" placeholder="Good"></label>
              <label>Name<input id="alignmentName" placeholder="Good"></label>
              <label>Value (+/-)<input id="alignmentValue" type="number" value="0"></label>
              <button id="createAlignmentBtn" class="primary">Add</button>
            </div>
          </div>
          <div class="stack">
            <h3>How it works</h3>
            <div class="muted">Sort is automatic. Use row actions to deactivate/reactivate or delete.</div>
          </div>
        </div>
        <div class="table-wrap" style="max-height:220px; margin-top:8px;">
          <table>
            <thead><tr><th>Code</th><th>Name</th><th>Value</th><th>State</th><th>Actions</th></tr></thead>
            <tbody id="alignmentBody"></tbody>
          </table>
        </div>
        <div id="alignmentStatus" class="status"></div>
      </div>

      <div class="card span-6" id="typesCard">
        <h2>Config: Guild Types</h2>
        <div class="split">
          <div class="stack">
            <h3>Add Type</h3>
            <div class="toolbar">
              <label>Code<input id="typeCode" placeholder="Guild"></label>
              <label>Name<input id="typeName" placeholder="Guild"></label>
              <button id="createTypeBtn" class="primary">Add</button>
            </div>
          </div>
          <div class="stack">
            <h3>How it works</h3>
            <div class="muted">Sort is automatic. Use row actions to deactivate/reactivate or delete.</div>
          </div>
        </div>
        <div class="table-wrap" style="max-height:220px; margin-top:8px;">
          <table>
            <thead><tr><th>Code</th><th>Name</th><th>State</th><th>Actions</th></tr></thead>
            <tbody id="typeBody"></tbody>
          </table>
        </div>
        <div id="typeStatus" class="status"></div>
      </div>

      <div class="card span-6" id="abandonCard">
        <h2>Pending Abandonment</h2>
        <div class="toolbar">
          <button id="refreshAbandonBtn">Refresh</button>
        </div>
        <div class="table-wrap" style="max-height:220px; margin-top:8px;">
          <table>
            <thead><tr><th>Guild</th><th>Requested By</th><th>Status</th><th>Actions</th></tr></thead>
            <tbody id="abandonBody"></tbody>
          </table>
        </div>
        <div id="abandonStatus" class="status"></div>
      </div>

      <div class="card span-6">
        <h2>Governance / Scheduler / Flags (Planned)</h2>
        <div class="stack muted">
          <div><strong>Motions/Votes:</strong> create, open, tally, apply.</div>
          <div><strong>Presence:</strong> present-window and quorum computation.</div>
          <div><strong>Check-ins:</strong> anti-cheat risk queue and moderation.</div>
          <div><strong>Procedural Generator:</strong> guildhall event feed and strength progression tuning.</div>
        </div>
      </div>
    </div>
  </section>
</main>

<script>
  const apiBase = <?php echo json_encode($apiBase, JSON_UNESCAPED_SLASHES); ?>;
  const tokenKey = "pq_admin_token_v1";
  document.getElementById("apiBaseLabel").textContent = apiBase;

  const state = {
    selectedAccountId: "",
  };

  function token() { return localStorage.getItem(tokenKey) || ""; }
  function setToken(v) { if (!v) localStorage.removeItem(tokenKey); else localStorage.setItem(tokenKey, v); }
  function setStatus(id, msg, ok) {
    const el = document.getElementById(id);
    el.textContent = msg || "";
    el.className = "status " + (msg ? (ok ? "ok" : "err") : "");
  }
  function headers(auth = false) {
    const h = { "Content-Type": "application/json" };
    if (auth && token()) h["Authorization"] = `Bearer ${token()}`;
    return h;
  }
  async function api(path, opts = {}) {
    const res = await fetch(`${apiBase}${path}`, opts);
    const json = await res.json().catch(() => ({ ok: false, error: { message: "Invalid JSON response" } }));
    if (!res.ok || !json.ok) {
      throw new Error((json.error && json.error.message) || `HTTP ${res.status}`);
    }
    return json.data || {};
  }
  function gotoCard(id) {
    document.getElementById(id).scrollIntoView({ behavior: "smooth", block: "start" });
  }

  async function refreshSession() {
    if (!token()) {
      document.getElementById("loginCard").classList.remove("hidden");
      document.getElementById("adminPanel").classList.add("hidden");
      document.getElementById("sessionBadge").textContent = "Not logged in";
      return;
    }
    try {
      const data = await api("/admin/session", { method: "GET", headers: headers(true) });
      document.getElementById("loginCard").classList.add("hidden");
      document.getElementById("adminPanel").classList.remove("hidden");
      document.getElementById("sessionBadge").textContent = `Admin: ${data.username}`;
      setStatus("loginStatus", "", true);
      await Promise.all([
        refreshAccounts(),
        refreshRealms(),
        refreshCharacters(),
        refreshGuilds(),
        refreshAlignments(),
        refreshTypes(),
        refreshPendingAbandonment(),
      ]);
    } catch (e) {
      setToken("");
      document.getElementById("loginCard").classList.remove("hidden");
      document.getElementById("adminPanel").classList.add("hidden");
      document.getElementById("sessionBadge").textContent = "Not logged in";
      setStatus("loginStatus", `Login/session failed: ${e.message}`, false);
    }
  }

  async function doLogin() {
    const username = document.getElementById("loginUser").value.trim();
    const password = document.getElementById("loginPass").value;
    if (!username || !password) {
      setStatus("loginStatus", "Username and password are required.", false);
      return;
    }
    try {
      const data = await api("/admin/login", {
        method: "POST",
        headers: headers(false),
        body: JSON.stringify({ username, password }),
      });
      setToken(data.token);
      setStatus("loginStatus", "Logged in.", true);
      await refreshSession();
    } catch (e) {
      setStatus("loginStatus", e.message, false);
    }
  }

  async function forceVerifyByEmail(email) {
    try {
      await api("/admin/force-verify", {
        method: "POST",
        headers: headers(true),
        body: JSON.stringify({ email }),
      });
      setStatus("accountsStatus", `Verified ${email}.`, true);
      await refreshAccounts();
    } catch (e) {
      setStatus("accountsStatus", e.message, false);
    }
  }

  async function refreshAccounts() {
    const q = document.getElementById("accountSearch").value.trim();
    const path = q ? `/admin/accounts?q=${encodeURIComponent(q)}&limit=200` : "/admin/accounts?limit=200";
    try {
      const data = await api(path, { method: "GET", headers: headers(true) });
      const body = document.getElementById("accountsBody");
      body.innerHTML = "";
      for (const a of (data.accounts || [])) {
        const tr = document.createElement("tr");
        tr.innerHTML = `
          <td>${a.email}</td>
          <td>${a.publicName || "-"}</td>
          <td>${a.verified ? '<span class="chip ok">verified</span>' : '<span class="chip err">not verified</span>'}</td>
          <td>
            <button data-act="chars" data-account="${a.accountId}">Characters</button>
            <button data-act="verify" data-email="${a.email}">Force Verify</button>
          </td>`;
        body.appendChild(tr);
      }
      body.querySelectorAll("button[data-act='chars']").forEach(btn => {
        btn.addEventListener("click", async () => {
          const accountId = btn.getAttribute("data-account") || "";
          document.getElementById("characterAccountFilter").value = accountId;
          state.selectedAccountId = accountId;
          gotoCard("charactersCard");
          await refreshCharacters();
        });
      });
      body.querySelectorAll("button[data-act='verify']").forEach(btn => {
        btn.addEventListener("click", async () => {
          await forceVerifyByEmail(btn.getAttribute("data-email") || "");
        });
      });
      setStatus("accountsStatus", `Loaded ${(data.accounts || []).length} account(s).`, true);
    } catch (e) {
      setStatus("accountsStatus", e.message, false);
    }
  }

  async function refreshRealms() {
    try {
      const data = await api("/admin/realms", { method: "GET", headers: headers(true) });
      const body = document.getElementById("realmsBody");
      body.innerHTML = "";
      for (const r of (data.realms || [])) {
        const tr = document.createElement("tr");
        tr.innerHTML = `<td>${r.realmId}</td><td>${r.name}</td><td>${r.status}</td><td>${r.supportsGuilds ? "yes" : "no"}</td>`;
        body.appendChild(tr);
      }
      setStatus("realmsStatus", `Loaded ${(data.realms || []).length} realm(s).`, true);
    } catch (e) {
      setStatus("realmsStatus", e.message, false);
    }
  }

  async function doCreateRealm() {
    const realmId = document.getElementById("realmId").value.trim();
    const name = document.getElementById("realmName").value.trim();
    const status = document.getElementById("realmStatus").value;
    if (!realmId || !name) {
      setStatus("realmsStatus", "realmId and name are required.", false);
      return;
    }
    try {
      await api("/admin/realms/create", {
        method: "POST",
        headers: headers(true),
        body: JSON.stringify({ realmId, name, status, supportsGuilds: true }),
      });
      setStatus("realmsStatus", `Created ${realmId}.`, true);
      await refreshRealms();
    } catch (e) {
      setStatus("realmsStatus", e.message, false);
    }
  }

  async function refreshCharacters() {
    const q = document.getElementById("characterSearch").value.trim();
    const accountId = document.getElementById("characterAccountFilter").value.trim();
    const params = new URLSearchParams({ limit: "200" });
    if (q) params.set("q", q);
    if (accountId) params.set("accountId", accountId);
    try {
      const data = await api(`/admin/characters?${params.toString()}`, { method: "GET", headers: headers(true) });
      const body = document.getElementById("charactersBody");
      body.innerHTML = "";
      for (const c of (data.characters || [])) {
        const tr = document.createElement("tr");
        tr.innerHTML = `
          <td>${c.name}<div class="muted">${c.race} ${c.className}</div></td>
          <td>${c.networkMode}</td>
          <td><button class="ghost" data-act="owner" data-account="${c.ownerAccountId}">${c.ownerEmail}</button></td>
          <td><button data-act="force-verify-owner" data-email="${c.ownerEmail}">Force Verify Owner</button></td>`;
        body.appendChild(tr);
      }
      body.querySelectorAll("button[data-act='owner']").forEach(btn => {
        btn.addEventListener("click", async () => {
          const accountId = btn.getAttribute("data-account") || "";
          document.getElementById("accountSearch").value = accountId;
          gotoCard("accountsCard");
          await refreshAccounts();
        });
      });
      body.querySelectorAll("button[data-act='force-verify-owner']").forEach(btn => {
        btn.addEventListener("click", async () => {
          await forceVerifyByEmail(btn.getAttribute("data-email") || "");
        });
      });
      setStatus("charactersStatus", `Loaded ${(data.characters || []).length} character(s).`, true);
    } catch (e) {
      setStatus("charactersStatus", e.message, false);
    }
  }

  async function refreshGuilds() {
    const q = document.getElementById("guildSearch").value.trim();
    const params = new URLSearchParams({ limit: "200" });
    if (q) params.set("q", q);
    try {
      const data = await api(`/admin/guilds?${params.toString()}`, { method: "GET", headers: headers(true) });
      const body = document.getElementById("guildsBody");
      body.innerHTML = "";
      for (const g of (data.guilds || [])) {
        const tr = document.createElement("tr");
        tr.innerHTML = `
          <td>${g.formalName}<div class="muted">${g.shortTag}</div></td>
          <td>${g.status}</td>
          <td><button class="ghost" data-act="goto-align" data-code="${g.alignmentCode}">${g.alignmentCode}</button></td>
          <td><button class="ghost" data-act="goto-type" data-code="${g.typeCode}">${g.typeCode}</button></td>
          <td>${g.activeMembers}</td>
          <td><button data-act="chief" data-chief="${g.chiefCharacterId}">${g.chiefName}</button></td>`;
        body.appendChild(tr);
      }
      body.querySelectorAll("button[data-act='goto-align']").forEach(btn => {
        btn.addEventListener("click", () => {
          document.getElementById("alignmentCode").value = btn.getAttribute("data-code") || "";
          gotoCard("alignmentCard");
        });
      });
      body.querySelectorAll("button[data-act='goto-type']").forEach(btn => {
        btn.addEventListener("click", () => {
          document.getElementById("typeCode").value = btn.getAttribute("data-code") || "";
          gotoCard("typesCard");
        });
      });
      body.querySelectorAll("button[data-act='chief']").forEach(btn => {
        btn.addEventListener("click", async () => {
          const chiefId = btn.getAttribute("data-chief") || "";
          document.getElementById("characterSearch").value = chiefId;
          gotoCard("charactersCard");
          await refreshCharacters();
        });
      });
      setStatus("guildsStatus", `Loaded ${(data.guilds || []).length} guild(s).`, true);
    } catch (e) {
      setStatus("guildsStatus", e.message, false);
    }
  }

  async function refreshAlignments() {
    try {
      const data = await api("/admin/config/alignment", { method: "GET", headers: headers(true) });
      const body = document.getElementById("alignmentBody");
      body.innerHTML = "";
      for (const a of (data.alignments || [])) {
        const tr = document.createElement("tr");
        tr.innerHTML = `
          <td>${a.code}</td>
          <td>${a.displayName}</td>
          <td>${a.alignmentValue}</td>
          <td>${a.include ? '<span class="chip ok">active</span>' : '<span class="chip">inactive</span>'}</td>
          <td>
            <button data-act="toggle" data-code="${a.code}" data-include="${a.include ? 0 : 1}">${a.include ? "Deactivate" : "Activate"}</button>
            <button data-act="delete" data-code="${a.code}">Delete</button>
          </td>`;
        body.appendChild(tr);
      }
      body.querySelectorAll("button[data-act='toggle']").forEach(btn => {
        btn.addEventListener("click", async () => {
          await toggleAlignment(btn.getAttribute("data-code") || "", (btn.getAttribute("data-include") || "0") === "1");
        });
      });
      body.querySelectorAll("button[data-act='delete']").forEach(btn => {
        btn.addEventListener("click", async () => {
          const code = btn.getAttribute("data-code") || "";
          if (!confirm(`Delete alignment ${code}?`)) return;
          await deleteAlignment(code);
        });
      });
      setStatus("alignmentStatus", `Loaded ${(data.alignments || []).length} alignment option(s).`, true);
    } catch (e) {
      setStatus("alignmentStatus", e.message, false);
    }
  }

  async function createAlignment() {
    const code = document.getElementById("alignmentCode").value.trim();
    const displayName = document.getElementById("alignmentName").value.trim();
    const alignmentValue = parseInt(document.getElementById("alignmentValue").value || "0", 10);
    if (!code || !displayName) {
      setStatus("alignmentStatus", "code and name are required.", false);
      return;
    }
    try {
      await api("/admin/config/alignment/create", {
        method: "POST",
        headers: headers(true),
        body: JSON.stringify({ code, displayName, alignmentValue }),
      });
      setStatus("alignmentStatus", `Added ${code}.`, true);
      await refreshAlignments();
    } catch (e) {
      setStatus("alignmentStatus", e.message, false);
    }
  }

  async function toggleAlignment(code, include) {
    try {
      await api("/admin/config/alignment/toggle", {
        method: "POST",
        headers: headers(true),
        body: JSON.stringify({ code, include }),
      });
      await refreshAlignments();
    } catch (e) {
      setStatus("alignmentStatus", e.message, false);
    }
  }

  async function deleteAlignment(code) {
    try {
      await api("/admin/config/alignment/delete", {
        method: "POST",
        headers: headers(true),
        body: JSON.stringify({ code }),
      });
      await refreshAlignments();
    } catch (e) {
      setStatus("alignmentStatus", e.message, false);
    }
  }

  async function refreshTypes() {
    try {
      const data = await api("/admin/config/type", { method: "GET", headers: headers(true) });
      const body = document.getElementById("typeBody");
      body.innerHTML = "";
      for (const t of (data.types || [])) {
        const tr = document.createElement("tr");
        tr.innerHTML = `
          <td>${t.code}</td>
          <td>${t.displayName}</td>
          <td>${t.include ? '<span class="chip ok">active</span>' : '<span class="chip">inactive</span>'}</td>
          <td>
            <button data-act="toggle" data-code="${t.code}" data-include="${t.include ? 0 : 1}">${t.include ? "Deactivate" : "Activate"}</button>
            <button data-act="delete" data-code="${t.code}">Delete</button>
          </td>`;
        body.appendChild(tr);
      }
      body.querySelectorAll("button[data-act='toggle']").forEach(btn => {
        btn.addEventListener("click", async () => {
          await toggleType(btn.getAttribute("data-code") || "", (btn.getAttribute("data-include") || "0") === "1");
        });
      });
      body.querySelectorAll("button[data-act='delete']").forEach(btn => {
        btn.addEventListener("click", async () => {
          const code = btn.getAttribute("data-code") || "";
          if (!confirm(`Delete type ${code}?`)) return;
          await deleteType(code);
        });
      });
      setStatus("typeStatus", `Loaded ${(data.types || []).length} type option(s).`, true);
    } catch (e) {
      setStatus("typeStatus", e.message, false);
    }
  }

  async function createType() {
    const code = document.getElementById("typeCode").value.trim();
    const displayName = document.getElementById("typeName").value.trim();
    if (!code || !displayName) {
      setStatus("typeStatus", "code and name are required.", false);
      return;
    }
    try {
      await api("/admin/config/type/create", {
        method: "POST",
        headers: headers(true),
        body: JSON.stringify({ code, displayName }),
      });
      setStatus("typeStatus", `Added ${code}.`, true);
      await refreshTypes();
    } catch (e) {
      setStatus("typeStatus", e.message, false);
    }
  }

  async function toggleType(code, include) {
    try {
      await api("/admin/config/type/toggle", {
        method: "POST",
        headers: headers(true),
        body: JSON.stringify({ code, include }),
      });
      await refreshTypes();
    } catch (e) {
      setStatus("typeStatus", e.message, false);
    }
  }

  async function deleteType(code) {
    try {
      await api("/admin/config/type/delete", {
        method: "POST",
        headers: headers(true),
        body: JSON.stringify({ code }),
      });
      await refreshTypes();
    } catch (e) {
      setStatus("typeStatus", e.message, false);
    }
  }

  async function refreshPendingAbandonment() {
    try {
      const data = await api("/admin/guilds/pending-abandonment", { method: "GET", headers: headers(true) });
      const body = document.getElementById("abandonBody");
      body.innerHTML = "";
      for (const g of (data.guilds || [])) {
        const tr = document.createElement("tr");
        tr.innerHTML = `
          <td>${g.formalName}<div class="muted">${g.guildId}</div></td>
          <td>${g.requestedBy || "-"}</td>
          <td>${g.status}</td>
          <td><button data-act="approve" data-guild="${g.guildId}">Approve</button></td>`;
        body.appendChild(tr);
      }
      body.querySelectorAll("button[data-act='approve']").forEach(btn => {
        btn.addEventListener("click", async () => {
          await approveAbandonment(btn.getAttribute("data-guild") || "");
        });
      });
      setStatus("abandonStatus", `Loaded ${(data.guilds || []).length} pending guild(s).`, true);
    } catch (e) {
      setStatus("abandonStatus", e.message, false);
    }
  }

  async function approveAbandonment(guildId) {
    try {
      await api("/admin/guilds/approve-abandonment", {
        method: "POST",
        headers: headers(true),
        body: JSON.stringify({ guildId }),
      });
      setStatus("abandonStatus", `Approved ${guildId}.`, true);
      await refreshPendingAbandonment();
      await refreshGuilds();
      await refreshCharacters();
    } catch (e) {
      setStatus("abandonStatus", e.message, false);
    }
  }

  document.getElementById("loginBtn").addEventListener("click", doLogin);
  document.getElementById("refreshAccountsBtn").addEventListener("click", refreshAccounts);
  document.getElementById("clearAccountFilterBtn").addEventListener("click", () => { document.getElementById("accountSearch").value = ""; refreshAccounts(); });
  document.getElementById("refreshRealmsBtn").addEventListener("click", refreshRealms);
  document.getElementById("createRealmBtn").addEventListener("click", doCreateRealm);
  document.getElementById("refreshCharactersBtn").addEventListener("click", refreshCharacters);
  document.getElementById("clearCharacterFilterBtn").addEventListener("click", () => {
    document.getElementById("characterSearch").value = "";
    document.getElementById("characterAccountFilter").value = "";
    refreshCharacters();
  });
  document.getElementById("refreshGuildsBtn").addEventListener("click", refreshGuilds);
  document.getElementById("createAlignmentBtn").addEventListener("click", createAlignment);
  document.getElementById("createTypeBtn").addEventListener("click", createType);
  document.getElementById("refreshAbandonBtn").addEventListener("click", refreshPendingAbandonment);

  refreshSession();
</script>
</body>
</html>
