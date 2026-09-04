#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------

locals {
  buckets           = { for b in var.s3_config : b.name => b }
  encrypted_buckets = { for k, b in local.buckets : k => b if b.encrypt }
  cloudfront_read   = { for k, b in local.buckets : k => b if b.allow_cloudfront_read }
  public_blocked    = { for k, b in local.buckets : k => b if b.block_public_access }
}
