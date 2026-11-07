// test/server.test.js
// WHY: Unit tests verify the HTTP handler logic without starting a real server.
// node:test is built into Node 20+ – no extra packages needed, keeping the image small.
// These tests also run in GitHub Actions on every push and pull request.

"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { handler } = require("../server");

// --------------------------------------------------------------------------
// Helper: create a lightweight mock of Node's req/res objects so we can
// call handler() directly without binding to a real TCP port.
// --------------------------------------------------------------------------
function makeReqRes(url, method = "GET") {
  const req = { url, method };

  // Capture the status code, headers and response body.
  let statusCode = null;
  const headers = {};
  const chunks = [];

  const res = {
    // writeHead records the HTTP status code and optional headers
    writeHead(code, hdrs = {}) {
      statusCode = code;
      if (hdrs) {
        for (const [k, v] of Object.entries(hdrs)) {
          headers[k.toLowerCase()] = v;
        }
      }
    },
    // end accumulates the response body (may be called multiple times).
    end(chunk) {
      if (chunk) chunks.push(chunk);
    },
    // Convenience getter so tests can read back the full body as a string.
    get body() {
      return chunks.join("");
    },
    get statusCode() {
      return statusCode;
    },
    get headers() {
      return headers;
    },
  };

  return { req, res };
}

// --------------------------------------------------------------------------
// Test 1 – GET /healthz must return HTTP 200 and { "status": "ok" }
// WHY: Kubernetes liveness/readiness probes and the Nagios plugin both rely
//      on this endpoint.  If it breaks, the pod gets killed and alerts fire.
// --------------------------------------------------------------------------
test("GET /healthz returns 200 and {status:ok}", () => {
  const { req, res } = makeReqRes("/healthz");
  handler(req, res);

  assert.equal(res.statusCode, 200, "status code should be 200");

  const body = JSON.parse(res.body);
  assert.deepEqual(body, { status: "ok" }, "body should be {status:'ok'}");
});

// --------------------------------------------------------------------------
// Test 2 – GET / must return HTTP 200 with app metadata
// WHY: Smoke-test that the root route works before we ship the image.
// --------------------------------------------------------------------------
test("GET / returns 200 and app metadata", () => {
  const { req, res } = makeReqRes("/");
  handler(req, res);

  assert.equal(res.statusCode, 200, "status code should be 200");

  const body = JSON.parse(res.body);
  assert.equal(body.app, "devops-demo", "app name should match");
  assert.ok(typeof body.version === "string", "version should be a string");
  assert.ok(typeof body.host === "string", "host should be a string");
});

// --------------------------------------------------------------------------
// Test 3 – Unknown paths must return HTTP 404
// WHY: Ensures we don't accidentally expose hidden routes and that any
//      misconfigured Nagios probe gets a clear error, not a false 200.
// --------------------------------------------------------------------------
test("unknown path returns 404", () => {
  const { req, res } = makeReqRes("/does-not-exist");
  handler(req, res);

  assert.equal(res.statusCode, 404, "status code should be 404");

  const body = JSON.parse(res.body);
  assert.equal(body.error, "not found", "error message should match");
});

// --------------------------------------------------------------------------
// Test 4 – GET /api/status returns 200 JSON with all keys, types and NO secrets
// WHY: Provides read-only status metrics for the dashboard.
// --------------------------------------------------------------------------
test("GET /api/status returns 200 JSON with expected keys, correct types, and no env secrets", () => {
  process.env.FAKE_SECRET_TOKEN = "super_secret_password_123";

  const { req, res } = makeReqRes("/api/status");
  handler(req, res);

  assert.equal(res.statusCode, 200, "status code should be 200");
  assert.equal(res.headers["content-type"], "application/json");
  assert.equal(res.headers["x-content-type-options"], "nosniff");

  const body = JSON.parse(res.body);
  assert.equal(body.app, "devops-demo");
  assert.equal(body.status, "ok");
  assert.ok(typeof body.version === "string", "version must be string");
  assert.ok(typeof body.host === "string", "host must be string");
  assert.ok(typeof body.nodeVersion === "string", "nodeVersion must be string");
  assert.ok(typeof body.platform === "string", "platform must be string");
  assert.ok(typeof body.uptimeSeconds === "number", "uptimeSeconds must be number");
  assert.ok(typeof body.memoryRssMb === "number", "memoryRssMb must be number");
  assert.ok(typeof body.startedAt === "string", "startedAt must be string");
  assert.ok(typeof body.now === "string", "now must be string");

  // Verify no environment variables, IP paths, or secrets are leaked
  const rawBody = res.body;
  assert.ok(!rawBody.includes("super_secret_password_123"), "must not leak process.env values");
  assert.ok(!rawBody.includes("FAKE_SECRET_TOKEN"), "must not leak env keys");

  delete process.env.FAKE_SECRET_TOKEN;
});

// --------------------------------------------------------------------------
// Test 5 – GET /dashboard returns 200 text/html with CSP and nosniff headers
// WHY: Dashboard page must have strict security headers.
// --------------------------------------------------------------------------
test("GET /dashboard returns 200 text/html with CSP, Cache-Control, and nosniff headers", () => {
  const { req, res } = makeReqRes("/dashboard");
  handler(req, res);

  assert.equal(res.statusCode, 200, "status code should be 200");
  assert.ok(res.headers["content-type"].includes("text/html"), "content-type must be text/html");
  assert.equal(res.headers["content-security-policy"], "default-src 'self'");
  assert.equal(res.headers["cache-control"], "no-store");
  assert.equal(res.headers["x-content-type-options"], "nosniff");
  assert.ok(res.body.includes("DevOps Platform Status"), "body must contain title");
  assert.ok(res.body.includes("health-badge"), "body must contain health badge");
});

// --------------------------------------------------------------------------
// Test 6 – GET /dashboard.css and /dashboard.js return 200 with correct content types
// WHY: Separate files ensure no inline scripts/styles needed with CSP 'self'.
// --------------------------------------------------------------------------
test("GET /dashboard.css and /dashboard.js return 200 with correct MIME types and nosniff", () => {
  const css = makeReqRes("/dashboard.css");
  handler(css.req, css.res);
  assert.equal(css.res.statusCode, 200);
  assert.ok(css.res.headers["content-type"].includes("text/css"));
  assert.equal(css.res.headers["x-content-type-options"], "nosniff");

  const js = makeReqRes("/dashboard.js");
  handler(js.req, js.res);
  assert.equal(js.res.statusCode, 200);
  assert.ok(js.res.headers["content-type"].includes("application/javascript"));
  assert.equal(js.res.headers["x-content-type-options"], "nosniff");
});

// --------------------------------------------------------------------------
// Test 7 – Non-GET method (POST /dashboard) returns 405 without crashing
// WHY: Read-only server should reject mutating HTTP methods gracefully.
// --------------------------------------------------------------------------
test("POST /dashboard returns 405 Method Not Allowed and does not crash", () => {
  const { req, res } = makeReqRes("/dashboard", "POST");
  assert.doesNotThrow(() => {
    handler(req, res);
  });
  assert.equal(res.statusCode, 405, "status code should be 405");
  const body = JSON.parse(res.body);
  assert.equal(body.error, "method not allowed");
});
