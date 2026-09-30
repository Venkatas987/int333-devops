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
function makeReqRes(url) {
  const req = { url };

  // Capture the status code and response body.
  let statusCode = null;
  const chunks = [];

  const res = {
    // writeHead records the HTTP status code (we ignore headers in tests).
    writeHead(code) {
      statusCode = code;
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
