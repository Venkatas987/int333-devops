// server.js
// WHY: This is the tiny app we wrap with the entire DevOps toolchain.
// Keeping the app simple lets students focus on the infrastructure, not the code.

const http = require("http");
const os = require("os");

const PORT = process.env.PORT || 3000;
const VERSION = process.env.APP_VERSION || "dev";

/**
 * handler - processes every incoming HTTP request.
 * Exported so the test file can call it without starting a real server.
 */
function handler(req, res) {
  // /healthz is polled by Kubernetes probes AND the Nagios plugin.
  // It must always return 200 + JSON {status:"ok"} while the app is healthy.
  if (req.url === "/healthz") {
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(JSON.stringify({ status: "ok" }));
  }

  // / is the main endpoint – shows app name, version (injected via env) and hostname.
  if (req.url === "/") {
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(
      JSON.stringify({ app: "devops-demo", version: VERSION, host: os.hostname() })
    );
  }

  // Anything else → 404.  Nagios and k8s probes should never hit this.
  res.writeHead(404, { "Content-Type": "application/json" });
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
