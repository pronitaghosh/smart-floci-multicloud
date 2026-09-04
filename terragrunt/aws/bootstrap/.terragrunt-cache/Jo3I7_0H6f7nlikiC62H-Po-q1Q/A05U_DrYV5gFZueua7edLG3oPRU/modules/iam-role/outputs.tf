#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "role_arns" {
  value = { for k, r in aws_iam_role.floci_iam_role : k => r.arn }
}

output "role_names" {
  value = { for k, r in aws_iam_role.floci_iam_role : k => r.name }
}
