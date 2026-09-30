# puppet/manifests/site.pp
#
# WHY THIS FILE EXISTS:
# site.pp is Puppet's entry point – every agent consults this file
# to determine which classes (and therefore which resources) apply to it.
#
# Puppet reads this file on the MASTER (or locally with `puppet apply`).
# The agent gets a compiled "catalog" – a list of desired resource states.
#
# Node matching:
#   node default      – applies to ALL hosts that don't match another node block.
#   node /^app.*/     – regex match; applies to hosts whose name starts with "app".
#
# WHY pull model: the agent runs every 30 minutes (by default) and enforces
# the catalog. If someone manually changes a file (drift), the next agent run
# corrects it automatically.

# ── Default node: every server gets the baseline class ────────────────────────
node default {
  # WHY `include` instead of `class {}`:
  # `include` is idempotent – including the same class twice is harmless.
  include baseline
}

# ── App servers: baseline + extra developer tools ─────────────────────────────
node /^app/ {
  include baseline

  # Extra packages only needed on the app server.
  package { ['jq', 'net-tools']:
    ensure => present,
  }
}
