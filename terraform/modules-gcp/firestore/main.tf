#------------------------------------------------------------------
# Module: Firestore (placeholder)
#------------------------------------------------------------------
# The emulator serves Firestore over gRPC only; Terraform create returns 404
# (proven Block 0). Databases are provisioned via SDK by the workloads and
# verified with API round-trips. Recorded in the compat gate list.
#------------------------------------------------------------------

locals {
  databases = {
    for d in var.firestore_config : d.name => d
  }
}
