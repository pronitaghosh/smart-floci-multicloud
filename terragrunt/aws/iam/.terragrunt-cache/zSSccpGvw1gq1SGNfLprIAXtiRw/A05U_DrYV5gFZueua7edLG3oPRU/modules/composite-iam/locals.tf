#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------

locals {
  config = yamldecode(var.config)
  global = local.config.global

  iam_config = try(local.config.iam_roles, [])
}
