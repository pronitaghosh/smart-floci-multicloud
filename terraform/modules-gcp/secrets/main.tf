#------------------------------------------------------------------
# Module: Secrets
#------------------------------------------------------------------
# Values are assembled by composite-stateful from this stack's own outputs,
# so this module performs no lookups.
#------------------------------------------------------------------

resource "google_secret_manager_secret" "floci_secret" {
  for_each = local.secrets

  secret_id = each.key

  replication {
    auto {}
  }

  labels = merge(
    var.global_config.labels,
    each.value.labels,
  )
}

resource "google_secret_manager_secret_version" "floci_version" {
  for_each = local.secrets

  secret      = google_secret_manager_secret.floci_secret[each.key].id
  secret_data = jsonencode(each.value.values)
}
