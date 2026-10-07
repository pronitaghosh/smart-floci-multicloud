#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "account_emails" {
  value = { for k, a in google_service_account.floci_account : k => a.email }
}

output "bound_roles" {
  value = { for k, m in google_project_iam_member.floci_member : k => m.role }
}
