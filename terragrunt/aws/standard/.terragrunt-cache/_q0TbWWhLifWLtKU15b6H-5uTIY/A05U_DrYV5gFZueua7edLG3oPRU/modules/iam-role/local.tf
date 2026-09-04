#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------

locals {
  roles = { for r in var.iam_config : r.name => r }

  # Flattened so a single for_each covers every (role, policy) pair. The key is
  # role/policy-arn, which is stable across reordering of either list.
  managed_attachments = merge([
    for name, r in local.roles : {
      for arn in r.managed_policy_arns : "${name}/${basename(arn)}" => {
        role_name  = name
        policy_arn = arn
      }
    }
  ]...)

  inline_policies = merge([
    for name, r in local.roles : {
      for p in r.inline_policies : "${name}/${p.name}" => {
        role_name = name
        policy    = p
      }
    }
  ]...)
}
