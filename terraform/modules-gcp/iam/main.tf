#------------------------------------------------------------------
# Module: GCP IAM
#------------------------------------------------------------------
# Bindings are created but never enforced locally: the emulator accepts any
# token. Pod access therefore flows through the documented emulator bypass in
# local mode; the same bindings govern real GCP with the compat flag off.
#------------------------------------------------------------------

resource "google_service_account" "floci_account" {
  for_each = local.accounts

  account_id   = each.key
  description  = each.value.description
  display_name = each.key
}

resource "google_project_iam_member" "floci_member" {
  for_each = local.bindings

  project = var.global_config.project
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.floci_account[each.value.account].email}"
}
