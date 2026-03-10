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
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 0; background: #f5f6f8; color: #111; }
    header { padding: 14px 18px; background: #131722; color: #fff; display:flex; justify-content:space-between; align-items:center; gap:12px; }
    main { padding: 18px; max-width: 1350px; margin: 0 auto; display:grid; gap:14px; }
    .grid { display:grid; grid-template-columns: repeat(auto-fit,minmax(320px,1fr)); gap:12px; }
    .full { grid-column: 1 / -1; }
    .card { background:#fff; border:1px solid #ddd; border-radius:10px; padding:12px; }
    h2 { margin: 0 0 10px; font-size: 16px; }
    input, select, button { font: inherit; padding: 7px 8px; border-radius: 8px; border:1px solid #c8ccd4; }
    input, select { width: 100%; box-sizing:border-box; }
    button { background:#fff; cursor:pointer; }
    button.primary { background:#131722; color:#fff; border-color:#131722; }
    .row { display:grid; grid-template-columns: 1fr 1fr auto; gap:8px; align-items:end; }
    .row2 { display:grid; grid-template-columns: 1fr auto; gap:8px; align-items:end; }
    .muted { color:#666; font-size: 13px; }
    .status { font-size: 13px; margin-top: 8px; min-height: 18px; }
    .ok { color: #0a7f2e; }
    .err { color: #b5162c; }
    table { width:100%; border-collapse: collapse; font-size: 13px; }
    th, td { text-align:left; border-bottom:1px solid #eee; padding: 6px 4px; }
    .hidden { display:none; }
    code { background:#f0f2f5; padding:1px 4px; border-radius:4px; }
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
    <section id="loginCard" class="card">
      <h2>Admin Login</h2>
      <div class="row">
        <label>
          Username
          <input id="loginUser" autocomplete="username" />
        </label>
        <label>
          Password
          <input id="loginPass" type="password" autocomplete="current-password" />
        </label>
        <button id="loginBtn" class="primary">Login</button>
      </div>
      <div id="loginStatus" class="status"></div>
    </section>

    <section id="adminPanel" class="hidden">
      <div class="grid">
        <div class="card full">
          <h2>Accounts</h2>
          <div class="row2">
            <label>
              Search (email/public name)
              <input id="accountSearch" placeholder="you@example.com" />
            </label>
            <button id="refreshAccountsBtn">Refresh</button>
          </div>
          <div style="max-height: 320px; overflow:auto; margin-top:10px;">
            <table>
              <thead>
                <tr><th>Email</th><th>Public Name</th><th>Verified</th><th>Created</th></tr>
              </thead>
              <tbody id="accountsBody"></tbody>
            </table>
          </div>
          <div id="accountsStatus" class="status"></div>
        </div>

        <div class="card">
          <h2>Force Verify Account</h2>
          <div class="row2">
            <label>
              Email
              <input id="forceVerifyEmail" placeholder="user@example.com" />
            </label>
            <button id="forceVerifyBtn" class="primary">Force Verify</button>
          </div>
          <div id="forceVerifyStatus" class="status"></div>
        </div>

        <div class="card">
          <h2>Realms</h2>
          <div class="row">
            <label>
              Realm ID
              <input id="realmId" value="realm_goobland_1" />
            </label>
            <label>
              Name
              <input id="realmName" value="Goobland" />
            </label>
            <button id="createRealmBtn" class="primary">Create Realm</button>
          </div>
          <div class="row2" style="margin-top:8px;">
            <label>
              Status
              <select id="realmStatus">
                <option value="active">active</option>
                <option value="coming_soon">coming_soon</option>
                <option value="disabled">disabled</option>
              </select>
            </label>
            <button id="refreshRealmsBtn">Refresh</button>
          </div>
          <div id="realmsStatus" class="status"></div>
          <div style="max-height: 240px; overflow:auto; margin-top:8px;">
            <table>
              <thead>
                <tr><th>ID</th><th>Name</th><th>Status</th><th>Guilds</th></tr>
              </thead>
              <tbody id="realmsBody"></tbody>
            </table>
          </div>
        </div>

        <div class="card">
          <h2>Characters (Placeholder)</h2>
          <p class="muted">Upcoming: searchable online-character records, ownership links, and moderation tools.</p>
        </div>
        <div class="card">
          <h2>Guilds (Placeholder)</h2>
          <p class="muted">Upcoming: guild roster browser, chief controls, and governance rule editing.</p>
        </div>
        <div class="card">
          <h2>Governance (Placeholder)</h2>
          <p class="muted">Upcoming: motions, votes, quorum snapshots, and meeting logs.</p>
        </div>
        <div class="card">
          <h2>Check-ins / Flags (Placeholder)</h2>
          <p class="muted">Upcoming: anti-cheat triage queue and review workflow.</p>
        </div>
        <div class="card">
          <h2>Config / Dictionaries (Placeholder)</h2>
          <p class="muted">Upcoming: alignments, guild types, and procedural term banks.</p>
        </div>
        <div class="card">
          <h2>Scheduler / Timers (Placeholder)</h2>
          <p class="muted">Upcoming: cron visibility and governance timing controls.</p>
        </div>
      </div>
    </section>
  </main>

  <script>
    const apiBase = <?php echo json_encode($apiBase, JSON_UNESCAPED_SLASHES); ?>;
    const tokenKey = "pq_admin_token_v1";
    document.getElementById("apiBaseLabel").textContent = apiBase;

    function token() { return localStorage.getItem(tokenKey) || ""; }
    function setToken(v) {
      if (!v) localStorage.removeItem(tokenKey);
      else localStorage.setItem(tokenKey, v);
    }
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
        await Promise.all([refreshAccounts(), refreshRealms()]);
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

    async function refreshAccounts() {
      const q = document.getElementById("accountSearch").value.trim();
      const path = q ? `/admin/accounts?q=${encodeURIComponent(q)}&limit=200` : "/admin/accounts?limit=200";
      try {
        const data = await api(path, { method: "GET", headers: headers(true) });
        const body = document.getElementById("accountsBody");
        body.innerHTML = "";
        for (const a of (data.accounts || [])) {
          const tr = document.createElement("tr");
          tr.innerHTML = `<td>${a.email}</td><td>${a.publicName || ""}</td><td>${a.verified ? "yes" : "no"}</td><td>${a.createdAt || ""}</td>`;
          body.appendChild(tr);
        }
        setStatus("accountsStatus", `Loaded ${(data.accounts || []).length} account(s).`, true);
      } catch (e) {
        setStatus("accountsStatus", e.message, false);
      }
    }

    async function doForceVerify() {
      const email = document.getElementById("forceVerifyEmail").value.trim();
      if (!email) {
        setStatus("forceVerifyStatus", "Email is required.", false);
        return;
      }
      try {
        await api("/admin/force-verify", {
          method: "POST",
          headers: headers(true),
          body: JSON.stringify({ email }),
        });
        setStatus("forceVerifyStatus", `Verified ${email}.`, true);
        await refreshAccounts();
      } catch (e) {
        setStatus("forceVerifyStatus", e.message, false);
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
        setStatus("realmsStatus", `Created realm ${realmId}.`, true);
        await refreshRealms();
      } catch (e) {
        setStatus("realmsStatus", e.message, false);
      }
    }

    document.getElementById("loginBtn").addEventListener("click", doLogin);
    document.getElementById("refreshAccountsBtn").addEventListener("click", refreshAccounts);
    document.getElementById("forceVerifyBtn").addEventListener("click", doForceVerify);
    document.getElementById("refreshRealmsBtn").addEventListener("click", refreshRealms);
    document.getElementById("createRealmBtn").addEventListener("click", doCreateRealm);

    refreshSession();
  </script>
</body>
</html>
