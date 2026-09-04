#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "certificate_arns" {
  value = { for k, c in aws_acm_certificate.floci_acm_certificate : k => c.arn }
}

output "domain_validation_options" {
  value = { for k, c in aws_acm_certificate.floci_acm_certificate : k => c.domain_validation_options }
}
