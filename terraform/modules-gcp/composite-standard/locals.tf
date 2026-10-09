#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------
# ArgoCD deferred to Block 6 per user decision; this stack owns GKE plus
# Cloud Run only. NodePort plus registration is the local access path;
# LB Terraform stays in Block 8. See compat gate 12.
#------------------------------------------------------------------

locals {
  config = yamldecode(var.config)
  global = {
    client_name = local.config.global.client_name
    environment = local.config.global.environment
    project     = local.config.global.project
    region      = local.config.global.region
    labels      = try(local.config.global.labels, {})
  }

  # Values resolved by earlier stacks, folded into the YAML under `resolved:`
  # by the standard leaf config. No cross-stack remote state.
  resolved = try(local.config.resolved, {})

  floci_compat = try(local.config.global.floci_compat, false)

  # --------------------------------------------------------------
  # GKE -- location defaults to region; node defaults live in module
  # --------------------------------------------------------------
  gke_config = [
    for c in try(local.config.clusters, []) : merge(c, {
      location = try(c.location, local.global.region)
    })
  ]

  # --------------------------------------------------------------
  # Cloud Run
  # --------------------------------------------------------------
  run_config = try(local.config.cloud_run_services, [])
}
