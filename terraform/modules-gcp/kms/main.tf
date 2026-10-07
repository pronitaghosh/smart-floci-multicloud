#------------------------------------------------------------------
# Module: GCP KMS
#------------------------------------------------------------------

resource "google_kms_key_ring" "floci_key_ring" {
  for_each = local.keys

  name     = "${var.global_config.client_name}-${each.key}"
  location = var.global_config.region
}

resource "google_kms_crypto_key" "floci_crypto_key" {
  for_each = local.keys

  name            = each.key
  key_ring        = google_kms_key_ring.floci_key_ring[each.key].id
  rotation_period = each.value.rotation_period
}
