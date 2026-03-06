<?php
declare(strict_types=1);
?><!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>PQ Multiplayer Admin</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 0; background: #f5f6f8; color: #111; }
    header { padding: 16px 20px; background: #131722; color: #fff; }
    main { padding: 20px; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px; }
    .card { background: #fff; border: 1px solid #ddd; border-radius: 10px; padding: 12px; }
    h2 { margin: 0 0 8px; font-size: 16px; }
    p { margin: 0; color: #444; font-size: 14px; }
    code { background: #f0f2f5; padding: 1px 4px; border-radius: 4px; }
  </style>
</head>
<body>
  <header>
    <strong>PQ Multiplayer Admin Scaffold</strong>
    <div>API target: <code>https://api.progressquest.me/api/v1</code></div>
  </header>
  <main>
    <div class="grid">
      <div class="card"><h2>Accounts</h2><p>Placeholder tab for account management.</p></div>
      <div class="card"><h2>Characters</h2><p>Placeholder tab for character records.</p></div>
      <div class="card"><h2>Guilds</h2><p>Placeholder tab for guild browsing and edits.</p></div>
      <div class="card"><h2>Governance</h2><p>Placeholder tab for motions/votes/presence.</p></div>
      <div class="card"><h2>Check-ins / Flags</h2><p>Placeholder tab for anti-cheat triage queue.</p></div>
      <div class="card"><h2>Config</h2><p>Placeholder tab for alignments/types/procedure data.</p></div>
      <div class="card"><h2>Scheduler</h2><p>Placeholder tab for timing defaults and cron visibility.</p></div>
    </div>
  </main>
</body>
</html>
