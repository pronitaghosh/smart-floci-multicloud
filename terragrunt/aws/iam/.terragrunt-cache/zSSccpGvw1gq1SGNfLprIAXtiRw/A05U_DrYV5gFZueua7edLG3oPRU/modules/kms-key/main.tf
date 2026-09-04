#------------------------------------------------------------------
# Module: KMS Key
#------------------------------------------------------------------

resource "aws_kms_key" "floci_kms_key" {
  for_each = local.keys

  description             = each.value.description
  deletion_window_in_days = each.value.deletion_window_in_days
  enable_key_rotation     = each.value.enable_key_rotation

  tags = merge(
    var.global_config.tags,
    each.value.tags,
    { Name = "${var.global_config.client_name}-${each.key}" }
  )
}

resource "aws_kms_alias" "floci_kms_alias" {
  for_each = local.keys

  name          = "alias/${var.global_config.client_name}-${each.key}"
  target_key_id = aws_kms_key.floci_kms_key[each.key].key_id
}
