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

#------------------------------------------------------------------
# Vault
#------------------------------------------------------------------

output "vault_unseal_key_ids" {
  value = module.stateful_vault.unseal_key_ids
}

output "vault_unseal_key_arns" {
  value = module.stateful_vault.unseal_key_arns
}

output "vault_root_token_secrets" {
  value = module.stateful_vault.root_token_secret_names
}

output "vault_recovery_key_secrets" {
  value = module.stateful_vault.recovery_keys_secret_names
}
