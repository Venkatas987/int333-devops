// server.js
// WHY: This is the tiny app we wrap with the entire DevOps toolchain.
// Keeping the app simple lets students focus on the infrastructure, not the code.

const http = require("http");
const os = require("os");

const PORT = process.env.PORT || 3000;
const VERSION = process.env.APP_VERSION || "dev";
const startedAt = new Date().toISOString();

const DASHBOARD_CSS = `
:root {
  --bg: #f8fafc;
  --card-bg: #ffffff;
  --text: #0f172a;
  --muted: #64748b;
  --border: #e2e8f0;
  --green: #16a34a;
  --green-bg: #dcfce7;
  --red: #dc2626;
  --red-bg: #fee2e2;
  --shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1);
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0f172a;
    --card-bg: #1e293b;
    --text: #f8fafc;
    --muted: #94a3b8;
    --border: #334155;
    --green: #22c55e;
    --green-bg: #14532d;
    --red: #ef4444;
    --red-bg: #7f1d1d;
    --shadow: 0 4px 6px -1px rgb(0 0 0 / 0.5);
  }
}

* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  background-color: var(--bg);
  color: var(--text);
  line-height: 1.5;
  padding: 1.5rem;
  max-width: 900px;
  margin: 0 auto;
}

header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  flex-wrap: wrap;
  gap: 1rem;
  margin-bottom: 2rem;
  padding-bottom: 1rem;
  border-bottom: 2px solid var(--border);
}

h1 { font-size: 1.75rem; font-weight: 700; }
.badge {
  font-size: 1.25rem;
  font-weight: 800;
  letter-spacing: 0.05em;
  padding: 0.5rem 1.25rem;
  border-radius: 9999px;
  text-transform: uppercase;
  transition: all 0.3s ease;
}
.badge.healthy { background: var(--green-bg); color: var(--green); border: 2px solid var(--green); }
.badge.down { background: var(--red-bg); color: var(--red); border: 2px solid var(--red); }
.badge.checking { background: var(--border); color: var(--muted); }

.grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 1rem;
  margin-bottom: 2rem;
}

.card {
  background: var(--card-bg);
  border: 1px solid var(--border);
  border-radius: 0.75rem;
  padding: 1.25rem;
  box-shadow: var(--shadow);
}

.card .label {
  font-size: 0.85rem;
  color: var(--muted);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  margin-bottom: 0.35rem;
}

.card .value {
  font-size: 1.35rem;
  font-weight: 600;
  word-break: break-all;
}

.served-banner {
  background: var(--card-bg);
  border: 1px solid var(--border);
  border-left: 6px solid var(--green);
  border-radius: 0.5rem;
  padding: 1rem 1.25rem;
  margin-bottom: 2rem;
  font-size: 1.05rem;
}

.served-banner strong {
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
}

footer {
  text-align: center;
  font-size: 0.85rem;
  color: var(--muted);
  margin-top: 3rem;
  padding-top: 1rem;
  border-top: 1px solid var(--border);
}
`;

const DASHBOARD_JS = `
function formatUptime(seconds) {
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  const parts = [];
  if (d > 0) parts.push(d + "d");
  if (h > 0) parts.push(h + "h");
  if (m > 0) parts.push(m + "m");
  parts.push(s + "s");
  return parts.join(" ");
}

async function updateDashboard() {
  const badge = document.getElementById("health-badge");
  const podName = document.getElementById("val-pod");
  const appVersion = document.getElementById("val-version");
  const uptime = document.getElementById("val-uptime");
  const memory = document.getElementById("val-memory");
  const nodeVer = document.getElementById("val-node");
  const platform = document.getElementById("val-platform");
  const lastUpdated = document.getElementById("val-updated");
  const servedPod = document.getElementById("served-pod");

  try {
    const healthRes = await fetch("/healthz");
    if (healthRes.ok) {
      badge.textContent = "HEALTHY";
      badge.className = "badge healthy";
    } else {
      badge.textContent = "DOWN";
      badge.className = "badge down";
    }
  } catch (err) {
    badge.textContent = "DOWN";
    badge.className = "badge down";
  }

  try {
    const statusRes = await fetch("/api/status");
    if (statusRes.ok) {
      const data = await statusRes.json();
      podName.textContent = data.host || "unknown";
      servedPod.textContent = data.host || "unknown";
      appVersion.textContent = data.version || "dev";
      uptime.textContent = formatUptime(data.uptimeSeconds || 0);
      memory.textContent = (data.memoryRssMb !== undefined ? data.memoryRssMb + " MB" : "N/A");
      nodeVer.textContent = data.nodeVersion || "N/A";
      platform.textContent = data.platform || "N/A";
      lastUpdated.textContent = new Date().toLocaleTimeString();
    }
  } catch (err) {
    lastUpdated.textContent = "Error fetching status";
  }
}

document.addEventListener("DOMContentLoaded", () => {
  updateDashboard();
  setInterval(updateDashboard, 5000);
});
`;

const DASHBOARD_HTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>DevOps Platform Status</title>
  <link rel="stylesheet" href="/dashboard.css">
</head>
<body>
  <header>
    <div>
      <h1>System Status</h1>
      <p style="color: var(--muted); font-size: 0.95rem;">Node.js Kubernetes Workload</p>
    </div>
    <div id="health-badge" class="badge checking">Checking...</div>
  </header>

  <div class="served-banner">
    Served by pod: <strong id="served-pod">loading...</strong> (refreshing every 5s)
  </div>

  <main class="grid">
    <div class="card">
      <div class="label">Pod Name</div>
      <div class="value" id="val-pod">-</div>
    </div>
    <div class="card">
      <div class="label">App Version</div>
      <div class="value" id="val-version">-</div>
    </div>
    <div class="card">
      <div class="label">Uptime</div>
      <div class="value" id="val-uptime">-</div>
    </div>
    <div class="card">
      <div class="label">Memory (RSS)</div>
      <div class="value" id="val-memory">-</div>
    </div>
    <div class="card">
      <div class="label">Node.js Runtime</div>
      <div class="value" id="val-node">-</div>
    </div>
    <div class="card">
      <div class="label">OS Platform</div>
      <div class="value" id="val-platform">-</div>
    </div>
    <div class="card">
      <div class="label">Last Updated</div>
      <div class="value" id="val-updated" style="font-size: 1.15rem;">-</div>
    </div>
  </main>

  <footer>
    Deployed with GitHub Actions, Docker, Terraform, Ansible, k3s, Puppet and Nagios
  </footer>

  <script src="/dashboard.js"></script>
</body>
</html>
`;

/**
 * handler - processes every incoming HTTP request.
 * Exported so the test file can call it without starting a real server.
 */
function handler(req, res) {
  // Only GET and HEAD requests are permitted on read-only endpoints
  if (req.method && req.method !== "GET" && req.method !== "HEAD") {
    res.writeHead(405, {
      "Content-Type": "application/json",
      "X-Content-Type-Options": "nosniff"
    });
    return res.end(JSON.stringify({ error: "method not allowed" }));
  }

  // /healthz is polled by Kubernetes probes AND the Nagios plugin.
  // It must always return 200 + JSON {status:"ok"} while the app is healthy.
  if (req.url === "/healthz") {
    res.writeHead(200, {
      "Content-Type": "application/json",
      "X-Content-Type-Options": "nosniff"
    });
    return res.end(JSON.stringify({ status: "ok" }));
  }

  // /api/status returns read-only runtime statistics (no secrets, no env, no IP paths)
  if (req.url === "/api/status") {
    const mem = process.memoryUsage();
    const statusPayload = {
      app: "devops-demo",
      version: VERSION,
      host: os.hostname(),
      status: "ok",
      nodeVersion: process.version,
      platform: os.platform(),
      uptimeSeconds: Math.round(process.uptime()),
      memoryRssMb: parseFloat((mem.rss / (1024 * 1024)).toFixed(1)),
      startedAt: startedAt,
      now: new Date().toISOString()
    };
    res.writeHead(200, {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff"
    });
    return res.end(JSON.stringify(statusPayload));
  }

  // /dashboard serves the self-contained status dashboard page
  if (req.url === "/dashboard") {
    res.writeHead(200, {
      "Content-Type": "text/html; charset=utf-8",
      "Content-Security-Policy": "default-src 'self'",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff"
    });
    return res.end(DASHBOARD_HTML);
  }

  // /dashboard.css serves the stylesheet for the dashboard
  if (req.url === "/dashboard.css") {
    res.writeHead(200, {
      "Content-Type": "text/css; charset=utf-8",
      "X-Content-Type-Options": "nosniff"
    });
    return res.end(DASHBOARD_CSS);
  }

  // /dashboard.js serves the client script for the dashboard
  if (req.url === "/dashboard.js") {
    res.writeHead(200, {
      "Content-Type": "application/javascript; charset=utf-8",
      "X-Content-Type-Options": "nosniff"
    });
    return res.end(DASHBOARD_JS);
  }

  // / is the main endpoint – shows app name, version (injected via env) and hostname.
  if (req.url === "/") {
    res.writeHead(200, {
      "Content-Type": "application/json",
      "X-Content-Type-Options": "nosniff"
    });
    return res.end(
      JSON.stringify({ app: "devops-demo", version: VERSION, host: os.hostname() })
    );
  }

  // Anything else → 404.  Nagios and k8s probes should never hit this.
  res.writeHead(404, {
    "Content-Type": "application/json",
    "X-Content-Type-Options": "nosniff"
  });
  res.end(JSON.stringify({ error: "not found" }));
}

// Only start the HTTP server when this file is run directly (not when required by tests).
if (require.main === module) {
  http.createServer(handler).listen(PORT, () =>
    console.log(`listening on ${PORT}`)
  );
}

// Export handler so unit tests can call it in-process without a network socket.
module.exports = { handler };
