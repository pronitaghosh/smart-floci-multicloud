#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "secret_ids" {
  value = { for k, s in google_secret_manager_secret.floci_secret : k => s.id }
}
