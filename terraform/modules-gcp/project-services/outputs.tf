#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "enabled_services" {
  value = [for s in google_project_service.floci_service : s.service]
}
