#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "vpc_id" {
  value = module.networking.vpc_id
}

output "subnet_ids" {
  value = module.networking.subnet_ids
}

output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.networking.private_subnet_ids
}

output "all_subnet_ids" {
  value = module.networking.all_subnet_ids
}

output "security_group_ids" {
  value = module.networking.security_group_ids
}

output "kms_key_arns" {
  value = module.kms_key.key_arns
}

output "ecr_repository_urls" {
  value = module.ecr_repository.repository_urls
}

output "bucket_ids" {
  value = module.s3_buckets.bucket_ids
}

output "bucket_regional_domain_names" {
  value = module.s3_buckets.bucket_regional_domain_names
}

output "acm_certificate_arns" {
  value = module.acm_certificate.certificate_arns
}

output "ssm_parameter_prefix" {
  value = module.ssm_parameters.parameter_prefix
}

#------------------------------------------------------------------
# Convenience outputs
#------------------------------------------------------------------
# The demo scripts and verify.sh address these by name. Keeping them as
# scalars alongside the keyed maps means splitting one root module into four
# stacks stayed invisible to everything downstream.
#------------------------------------------------------------------

output "frontend_bucket" {
  value = try(values(module.s3_buckets.bucket_ids)[0], null)
}

output "kms_key_arn" {
  value = try(values(module.kms_key.key_arns)[0], null)
}

output "acm_certificate_arn" {
  value = try(values(module.acm_certificate.certificate_arns)[0], null)
}
