#------------------------------------------------------------------
# Module: Stateful Vault
#------------------------------------------------------------------
# The AWS half of a Vault deployment: the auto-unseal key and the secret
# containers its root token lands in. Deliberately separate from the runtime
# half (../vault) because these outlive any particular cluster.
#------------------------------------------------------------------

resource "aws_kms_key" "floci_vault_unseal_key" {
  for_each = local.clusters

  description             = "${each.key} Vault auto-unseal"
  deletion_window_in_days = each.value.unseal_key_deletion_window
  enable_key_rotation     = true

  tags = merge(
    var.global_config.tags,
    each.value.tags,
    { Name = "${each.key}-vault-unseal" }
  )
}

resource "aws_kms_alias" "floci_vault_unseal_alias" {
  for_each = local.clusters

  name          = "alias/${each.key}-vault-unseal"
  target_key_id = aws_kms_key.floci_vault_unseal_key[each.key].key_id
}

#------------------------------------------------------------------
# Secret containers
#------------------------------------------------------------------
# Values are written after `vault operator init` by the runtime module's
# provisioner. Terraform owns the container; it never sees the contents.
#------------------------------------------------------------------

resource "aws_secretsmanager_secret" "floci_vault_root_token" {
  for_each = local.root_token_secrets

  name                    = "${each.key}-vault-root-token"
  description             = "Root token for the ${each.key} Vault cluster"
  recovery_window_in_days = 0

  tags = merge(
    var.global_config.tags,
    each.value.tags,
    { Name = "${each.key}-vault-root-token" }
  )
}

resource "aws_secretsmanager_secret" "floci_vault_recovery_keys" {
  for_each = local.recovery_secrets

  name                    = "${each.key}-vault-recovery-keys"
  description             = "Recovery keys for the ${each.key} Vault cluster"
  recovery_window_in_days = 0

  tags = merge(
    var.global_config.tags,
    each.value.tags,
    { Name = "${each.key}-vault-recovery-keys" }
  )
}
