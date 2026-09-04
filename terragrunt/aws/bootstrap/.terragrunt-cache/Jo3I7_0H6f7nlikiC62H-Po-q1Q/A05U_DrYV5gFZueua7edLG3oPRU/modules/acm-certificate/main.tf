#------------------------------------------------------------------
# Module: ACM Certificate
#------------------------------------------------------------------

resource "aws_acm_certificate" "floci_acm_certificate" {
  for_each = local.certificates

  domain_name       = each.value.domain_name
  validation_method = each.value.validation_method

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.global_config.tags,
    each.value.tags,
    { Name = "${var.global_config.client_name}-${each.key}" }
  )
}
