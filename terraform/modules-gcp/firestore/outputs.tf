#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "database_names" {
  description = "Declared databases pending SDK provisioning"
  value       = [for k, d in local.databases : k]
}
