#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "repository_urls" {
  value = { for k, r in aws_ecr_repository.floci_ecr_repository : k => r.repository_url }
}

output "repository_arns" {
  value = { for k, r in aws_ecr_repository.floci_ecr_repository : k => r.arn }
}
