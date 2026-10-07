#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------

locals {
  name = var.network_config.name

  # Keyed maps drive every for_each below. Keys are stable, human-readable and
  # derived from config -- never from list position.
  subnets = {
    for s in var.network_config.subnets : s.name => s
  }

  firewall_rules = {
    for f in var.network_config.firewall_rules : f.name => f
  }
}
