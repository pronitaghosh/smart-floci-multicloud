#------------------------------------------------------------------
# Module: GCP Artifact Registry (placeholder)
#------------------------------------------------------------------
# The emulator returns 404 for repository create via Terraform and REST
# (proven Block 0, re-proven Block 3). This module publishes the address
# pattern only; real repositories are created in Block 6 through the
# documented registry flow. Recorded in the compat gate list.
#------------------------------------------------------------------

locals {
  repositories = {
    for r in var.registry_config : r.name => r
  }
}
