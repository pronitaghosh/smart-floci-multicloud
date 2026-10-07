#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------

locals {
  buckets = {
    for b in var.bucket_config : b.name => b
  }

  lifecycle_buckets = {
    for k, b in local.buckets : k => b if b.lifecycle_age_days != null
  }
}
