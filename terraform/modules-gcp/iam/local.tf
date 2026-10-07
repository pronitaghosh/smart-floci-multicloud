#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------
# Binding keys derive from config strings only, so for_each keys stay known
# at plan time while member emails resolve after the accounts apply.
#------------------------------------------------------------------

locals {
  accounts = {
    for a in var.iam_config.service_accounts : a.name => a
  }

  bindings = merge([
    for b in var.iam_config.bindings : {
      for r in b.roles : "${b.account}--${r}" => {
        account = b.account
        role    = r
      }
    }
  ]...)
}
