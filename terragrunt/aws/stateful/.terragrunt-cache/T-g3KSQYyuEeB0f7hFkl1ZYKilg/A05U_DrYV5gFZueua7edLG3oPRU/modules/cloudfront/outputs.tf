#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "distribution_domain_names" {
  value = { for k, d in aws_cloudfront_distribution.floci_cloudfront_distribution : k => d.domain_name }
}

output "distribution_ids" {
  value = { for k, d in aws_cloudfront_distribution.floci_cloudfront_distribution : k => d.id }
}
