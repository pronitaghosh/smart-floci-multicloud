#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------
# ArgoCD platform releases land here in Block 6; the Application owns k8s/gcp
# while rendered Secret-derived config stays imperative. NodePort plus
# registration is the local access path; LB Terraform stays in Block 8.
# See compat gates 12 and 16.
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

  # --------------------------------------------------------------
  # ArgoCD -- the password hook reaches the emulator over the host
  # endpoint; local-exec runs on the host, not in the cluster.
  # --------------------------------------------------------------
  argocd_config = [
    for a in try(local.config.argocd, []) : merge(a, {
      gcp_endpoint_url = "http://localhost:4588"
      gcp_project      = local.global.project
    })
  ]
}
