#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "bucket_ids" {
  value = { for k, b in google_storage_bucket.floci_bucket : k => b.id }
}

output "bucket_urls" {
  value = { for k, b in google_storage_bucket.floci_bucket : k => b.url }
}
