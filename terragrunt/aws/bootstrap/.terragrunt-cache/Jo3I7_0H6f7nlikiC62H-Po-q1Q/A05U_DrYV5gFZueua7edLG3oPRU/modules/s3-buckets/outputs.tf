#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "bucket_ids" {
  value = { for k, b in aws_s3_bucket.floci_bucket : k => b.id }
}

output "bucket_arns" {
  value = { for k, b in aws_s3_bucket.floci_bucket : k => b.arn }
}

output "bucket_regional_domain_names" {
  value = { for k, b in aws_s3_bucket.floci_bucket : k => b.bucket_regional_domain_name }
}
