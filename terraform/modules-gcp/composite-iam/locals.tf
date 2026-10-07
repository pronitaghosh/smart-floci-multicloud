#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------

locals {
  config = yamldecode(var.config)
  global = {
    client_name = local.config.global.client_name
    environment = local.config.global.environment
    project     = local.config.global.project
    region      = local.config.global.region
    labels      = try(local.config.global.labels, {})
  }

  iam_config = {
    service_accounts = try(local.config.service_accounts, [])
    bindings         = try(local.config.project_iam_bindings, [])
  }
}
