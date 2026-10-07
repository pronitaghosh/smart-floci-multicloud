#------------------------------------------------------------------
# Module: GCP Bucket
#------------------------------------------------------------------

resource "google_storage_bucket" "floci_bucket" {
  for_each = local.buckets

  name     = each.key
  location = var.global_config.region

  versioning {
    enabled = each.value.versioning
  }

  public_access_prevention    = each.value.public_access_prevention
  uniform_bucket_level_access = each.value.uniform_bucket_level_access

  labels = merge(
    var.global_config.labels,
    each.value.labels,
  )

  dynamic "lifecycle_rule" {
    for_each = each.value.lifecycle_age_days != null ? [each.value.lifecycle_age_days] : []

    content {
      action {
        type = "Delete"
      }

      condition {
        age = lifecycle_rule.value
      }
    }
  }
}
