# Dockerfile
# WHY: We use a multi-stage build so the final image is as small and secure as possible.
#
# Stage 1 (builder): installs production dependencies with `npm ci`.
#   Since this app has no third-party packages, node_modules is empty –
#   but keeping the npm ci step ensures the build is reproducible and
#   will work correctly if packages are added later.
# Stage 2 (runtime): copies ONLY the app files (no dev tools, no build cache).
#   The result is a tiny Alpine image running as the unprivileged "node" user.

# ─── Stage 1: builder ────────────────────────────────────────────────────────
FROM node:22-alpine AS builder

WORKDIR /app

# Copy manifests first so Docker's layer cache reuses the npm ci layer
# on subsequent builds when only source code (not dependencies) changed.
COPY package.json package-lock.json ./

# `npm ci` (clean install) is stricter than `npm install`.
# --omit=dev: skips devDependencies so the final node_modules is production-only.
# WHY: Even if there are zero dependencies, this guarantees the build is reproducible.
RUN npm ci --omit=dev

# ─── Stage 2: runtime ────────────────────────────────────────────────────────
FROM node:22-alpine AS runtime

# Remove npm, npx, and corepack from the runtime stage.
# WHY: The runtime image only requires the `node` binary to execute server.js.
# Bundled build-time tools (npm/corepack) carry high/critical CVEs in their dependencies
# and are unnecessary in production, increasing container attack surface.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack

# Tell Node.js it's running in production – enables optimisations,
# and stops Express (if added later) from serving stack traces.
ENV NODE_ENV=production

WORKDIR /app

# NOTE: This app has no runtime dependencies in package.json, so no node_modules
# folder exists or is copied. We copy package.json from the builder stage.
# --chown=node:node sets file ownership to the non-root "node" user.
COPY --from=builder --chown=node:node /app/package.json ./package.json

# Copy application source.
COPY --chown=node:node server.js ./

# Switch to the unprivileged "node" user.
# WHY: Running as root in a container is a security risk; if the process is
#      compromised, the attacker gets root on the host (with some effort).
USER node

# Document that the app listens on 3000 (doesn't actually publish the port).
EXPOSE 3000

# HEALTHCHECK lets `docker run` and Kubernetes know how to check the app.
# --interval=30s  : check every 30 seconds
# --timeout=5s    : fail the check if no response within 5 seconds
# --start-period=5s : give the app 5 seconds to start before the first check
# --retries=3     : mark UNHEALTHY only after 3 consecutive failures
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:3000/healthz || exit 1

# Start the application.
CMD ["node", "server.js"]
