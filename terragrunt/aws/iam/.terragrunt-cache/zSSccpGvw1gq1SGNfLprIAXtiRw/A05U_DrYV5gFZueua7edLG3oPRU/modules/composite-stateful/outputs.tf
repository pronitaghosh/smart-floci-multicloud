#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "rds_endpoints" {
  value = module.rds.endpoints
}

output "rds_endpoint" {
  value = try(values(module.rds.endpoints)[0], null)
}

output "redis_endpoints" {
  value = module.elasticache.primary_endpoints
}

output "redis_endpoint" {
  value = try(values(module.elasticache.primary_endpoints)[0], null)
}

output "app_secret_arn" {
  value = try(values(module.secrets_manager.secret_arns)[0], null)
}

output "secret_arns" {
  value = module.secrets_manager.secret_arns
}
