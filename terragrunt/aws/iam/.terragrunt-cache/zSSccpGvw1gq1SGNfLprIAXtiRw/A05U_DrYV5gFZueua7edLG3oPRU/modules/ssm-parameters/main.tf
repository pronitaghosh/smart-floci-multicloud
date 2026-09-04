#------------------------------------------------------------------
# Module: SSM Parameters
#------------------------------------------------------------------

resource "aws_ssm_parameter" "floci_ssm_parameter" {
  for_each = local.parameters

  name  = each.key
  type  = each.value.type
  value = each.value.value

  tags = merge(
    var.global_config.tags,
    each.value.tags
  )
}
