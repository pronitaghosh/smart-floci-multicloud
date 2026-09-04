#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------

locals {
  clusters      = { for c in var.elasticache_config : c.name => c }
  subnet_groups = { for k, c in local.clusters : k => c if c.create_subnet_group }
}
