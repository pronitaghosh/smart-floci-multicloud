#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "endpoints" {
  value = { for k, i in aws_db_instance.floci_db_instance : k => i.endpoint }
}

output "db_names" {
  value = { for k, i in aws_db_instance.floci_db_instance : k => i.db_name }
}

output "usernames" {
  value = { for k, i in aws_db_instance.floci_db_instance : k => i.username }
}
