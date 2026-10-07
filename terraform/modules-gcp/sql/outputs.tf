#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "instance_names" {
  value = { for k, i in google_sql_database_instance.floci_sql : k => i.name }
}

output "connection_names" {
  value = { for k, i in google_sql_database_instance.floci_sql : k => i.connection_name }
}

output "db_names" {
  value = { for k, d in google_sql_database.floci_db : k => d.name }
}

output "usernames" {
  value = { for k, u in google_sql_user.floci_user : k => u.name }
}
