#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "repository_urls" {
  description = "Placeholder addresses pending the Block 6 registry flow"
  value = {
    for k, r in local.repositories :
    k => "${var.global_config.region}-docker.pkg.dev/${var.global_config.project}/${k}"
  }
}
