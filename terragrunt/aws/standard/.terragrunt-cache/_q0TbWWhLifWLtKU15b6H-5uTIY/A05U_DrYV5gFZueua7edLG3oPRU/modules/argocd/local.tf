#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------

locals {
  installs = { for a in var.argocd_config : a.name => a }

  password_secrets = {
    for k, a in local.installs : k => a if a.admin_password_secret_name != ""
  }
}
