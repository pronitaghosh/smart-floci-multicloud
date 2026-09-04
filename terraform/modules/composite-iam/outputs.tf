#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "role_arns" {
  value = module.iam_role.role_arns
}

output "role_names" {
  value = module.iam_role.role_names
}

#------------------------------------------------------------------
# Convenience outputs
#------------------------------------------------------------------

output "app_role_arn" {
  value = try(module.iam_role.role_arns["${yamldecode(var.config).global.client_name}-cluster-app-role"], null)
}
