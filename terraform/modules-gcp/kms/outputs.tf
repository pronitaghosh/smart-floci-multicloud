#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "key_ring_ids" {
  value = { for k, r in google_kms_key_ring.floci_key_ring : k => r.id }
}

output "crypto_key_ids" {
  value = { for k, v in google_kms_crypto_key.floci_crypto_key : k => v.id }
}
