# puppet/modules/baseline/manifests/init.pp
#
# WHY THIS CLASS EXISTS:
# A Puppet class is a named collection of resources.
# The `baseline` class enforces a minimal, secure configuration on every server:
#   - Essential packages are installed
#   - chrony (time sync) is running
#   - /etc/motd (message of the day) is rendered from a template
#   - A deploy user exists for CI/CD deployments
#
# TYPED PARAMETERS with defaults make the class reusable:
#   class { 'baseline': packages => ['vim', 'htop'] }
# or just:
#   include baseline   (uses defaults)

class baseline (
  # List of packages to install on every server.
  Array[String] $packages = ['curl', 'git', 'htop', 'chrony', 'unattended-upgrades'],

  # The name of the NTP service (differs between distros; chrony on Ubuntu 22.04).
  String $ntp_svc = 'chrony',

  # In systemd environments (e.g. real EC2), service_provider is 'systemd'.
  # In container test environments without systemd, services cannot run persistently.
  Boolean $manage_service = ($facts['service_provider'] == 'systemd'),
) {

  # ── Packages ────────────────────────────────────────────────────────────────
  # WHY ensure => present: idempotent – Puppet only installs if not already there.
  package { $packages:
    ensure => present,
  }

  # ── NTP service ─────────────────────────────────────────────────────────────
  # WHY `require => Package[$ntp_svc]`:
  # Puppet uses this to set the dependency order.
  # The service resource won't be managed until the package is installed.
  if $manage_service {
    service { $ntp_svc:
      ensure  => running,
      enable  => true,
      require => Package[$ntp_svc],
    }
  }

  # ── Environment label ────────────────────────────────────────────────────────
  # WHY a custom function?  It encapsulates the hostname → environment label
  # mapping in reusable Ruby code rather than an ugly if/elsif chain in Puppet.
  # See: modules/baseline/lib/puppet/functions/baseline/env_label.rb
  $env_label = baseline::env_label($facts['networking']['hostname'])

  # ── Message of the Day ───────────────────────────────────────────────────────
  # WHY a template?  ERB templates can embed Ruby logic and access Facter facts.
  # The generated /etc/motd tells admins which server they're on and its role.
  file { '/etc/motd':
    ensure  => file,
    content => epp('baseline/motd.epp', {
      'hostname'   => $facts['networking']['hostname'],
      'env_label'  => $env_label,
      'os_name'    => $facts['os']['name'],
      'os_release' => $facts['os']['release']['full'],
      'memory_mb'  => $facts['memory']['system']['total_bytes'] / 1048576,
      'cpu_count'  => $facts['processors']['count'],
    }),
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
  }

  # ── Deploy user ──────────────────────────────────────────────────────────────
  # WHY: A dedicated deploy user with no login shell is a security best practice.
  # CI/CD tools can use this account without needing root or the ubuntu user.
  user { 'deploy':
    ensure     => present,
    comment    => 'CI/CD deploy user',
    shell      => '/usr/sbin/nologin',
    managehome => true,
    system     => false,
  }
}
