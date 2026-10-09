#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "service_names" {
  value = { for k, s in google_cloud_run_v2_service.floci_run : k => s.name }
}

output "service_uris" {
  value = { for k, s in google_cloud_run_v2_service.floci_run : k => s.uri }
}
