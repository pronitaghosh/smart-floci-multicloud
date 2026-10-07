#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "network_id" {
  value = module.networking.network_id
}

output "subnet_ids" {
  value = module.networking.subnet_ids
}

output "firewall_ids" {
  value = module.networking.firewall_ids
}

output "kms_key_ring_ids" {
  value = module.kms.key_ring_ids
}

output "kms_crypto_key_ids" {
  value = module.kms.crypto_key_ids
}

output "registry_repository_urls" {
  value = module.registry.repository_urls
}

output "bucket_ids" {
  value = module.bucket.bucket_ids
}

output "enabled_services" {
  value = module.project_services.enabled_services
}

#------------------------------------------------------------------
# Convenience outputs
#------------------------------------------------------------------

output "frontend_bucket" {
  value = try(values(module.bucket.bucket_ids)[0], null)
}

output "kms_crypto_key" {
  value = try(values(module.kms.crypto_key_ids)[0], null)
}
