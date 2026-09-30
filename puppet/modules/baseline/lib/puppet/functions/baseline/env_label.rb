# puppet/modules/baseline/lib/puppet/functions/baseline/env_label.rb
#
# WHY THIS FILE EXISTS:
# This is a custom Puppet 4.x (modern) function written in Ruby.
# It maps a server's hostname to a human-readable environment label.
#
# Why a custom function instead of a class parameter or Hiera?
#   - It encapsulates business logic in one place.
#   - It can be called anywhere in manifests: $label = baseline::env_label($hostname)
#   - It demonstrates the `puppet/functions` API required by the INT333 syllabus.
#
# Function API:
#   baseline::env_label(String $hostname) -> String
#
# Mapping logic:
#   hostname contains "prod"    → PRODUCTION
#   hostname contains "staging" → STAGING
#   hostname contains "dev"     → DEVELOPMENT
#   hostname starts with app/mon (no env) → STAGING
#   anything else (e.g. ip-*)   → DEVELOPMENT

Puppet::Functions.create_function(:'baseline::env_label') do
  # Declare the parameter type – Puppet will validate this before calling Ruby.
  dispatch :env_label do
    param 'String', :hostname
    return_type 'String'
  end

  # The implementation method (must match the dispatch name).
  def env_label(hostname)
    case hostname
    when /prod/i
      'PRODUCTION'
    when /staging/i
      'STAGING'
    when /dev/i
      'DEVELOPMENT'
    when /^app/i, /^mon/i
      'STAGING'
    else
      'DEVELOPMENT'
    end
  end
end
