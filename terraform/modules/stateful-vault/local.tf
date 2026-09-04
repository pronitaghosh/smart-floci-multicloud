#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------

locals {
  clusters = { for v in var.vault_static_config : v.name => v }

  root_token_secrets = { for k, v in local.clusters : k => v if v.store_root_token }
  recovery_secrets   = { for k, v in local.clusters : k => v if v.store_recovery_keys }
}
