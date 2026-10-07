#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "account_emails" {
  value = module.iam.account_emails
}

output "bound_roles" {
  value = module.iam.bound_roles
}

#------------------------------------------------------------------
# Convenience outputs
#------------------------------------------------------------------

output "app_account_email" {
  value = try(module.iam.account_emails["smartcloud-app"], null)
}
