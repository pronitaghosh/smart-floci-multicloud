#------------------------------------------------------------------
# Module: GCP Project Services
#------------------------------------------------------------------

resource "google_project_service" "floci_service" {
  for_each = toset(var.services_config)

  service = each.key

  disable_on_destroy = false
}
