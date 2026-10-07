#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "sql_connection_names" {
  value = module.sql.connection_names
}

output "sql_db_names" {
  value = module.sql.db_names
}

output "firestore_databases" {
  value = module.firestore.database_names
}

output "pubsub_topic_ids" {
  value = module.pubsub.topic_ids
}

output "pubsub_subscription_ids" {
  value = module.pubsub.subscription_ids
}

output "secret_ids" {
  value = module.secrets.secret_ids
}

#------------------------------------------------------------------
# Convenience outputs
#------------------------------------------------------------------

output "app_secret_id" {
  value = try(module.secrets.secret_ids["smartcloud-app-credentials"], null)
}
