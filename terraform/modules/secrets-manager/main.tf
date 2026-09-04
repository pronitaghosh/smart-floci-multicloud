#------------------------------------------------------------------
# Module: Secrets Manager
#------------------------------------------------------------------

resource "aws_secretsmanager_secret" "floci_secret" {
  for_each = local.secrets

  name                    = each.key
  description             = each.value.description
  kms_key_id              = each.value.kms_key_arn
  recovery_window_in_days = each.value.recovery_window_in_days

  tags = merge(
    var.global_config.tags,
    each.value.tags,
    { Name = each.key }
  )
}

resource "aws_secretsmanager_secret_version" "floci_secret_version" {
  for_each = local.secrets

  secret_id     = aws_secretsmanager_secret.floci_secret[each.key].id
  secret_string = jsonencode(each.value.values)
}
