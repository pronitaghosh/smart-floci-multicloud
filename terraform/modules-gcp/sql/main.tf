#------------------------------------------------------------------
# Module: Cloud SQL
#------------------------------------------------------------------
# Docker-backed data plane via the emulator; the instance spawns a Postgres
# sidecar. private_network stays null locally (compat gate); set it for real
# GCP behind the compat flag.
#------------------------------------------------------------------

resource "google_sql_database_instance" "floci_sql" {
  for_each = local.instances

  name             = each.key
  database_version = each.value.database_version
  region           = var.global_config.region

  settings {
    tier = each.value.tier

    dynamic "ip_configuration" {
      for_each = each.value.private_network == null ? [] : [each.value.private_network]

      content {
        private_network = ip_configuration.value
      }
    }
  }

  deletion_protection = false
}

resource "google_sql_database" "floci_db" {
  for_each = local.instances

  name     = each.value.database_name
  instance = google_sql_database_instance.floci_sql[each.key].name
}

resource "google_sql_user" "floci_user" {
  for_each = local.instances

  name     = each.value.username
  instance = google_sql_database_instance.floci_sql[each.key].name
  password = each.value.password
}
