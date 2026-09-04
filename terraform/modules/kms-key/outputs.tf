#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "key_arns" {
  value = { for k, v in aws_kms_key.floci_kms_key : k => v.arn }
}

output "key_ids" {
  value = { for k, v in aws_kms_key.floci_kms_key : k => v.key_id }
}

output "alias_names" {
  value = { for k, v in aws_kms_alias.floci_kms_alias : k => v.name }
}
