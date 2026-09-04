#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "unseal_key_arns" {
  value = { for k, v in aws_kms_key.floci_vault_unseal_key : k => v.arn }
}

output "unseal_key_ids" {
  value = { for k, v in aws_kms_key.floci_vault_unseal_key : k => v.key_id }
}

output "root_token_secret_names" {
  value = { for k, s in aws_secretsmanager_secret.floci_vault_root_token : k => s.name }
}

output "recovery_keys_secret_names" {
  value = { for k, s in aws_secretsmanager_secret.floci_vault_recovery_keys : k => s.name }
}
