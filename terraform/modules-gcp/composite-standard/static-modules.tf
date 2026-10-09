#------------------------------------------------------------------
# Module: GKE
#------------------------------------------------------------------

module "gke" {
  source = "../gke"

  global_config = local.global
  gke_config    = local.gke_config
}

#------------------------------------------------------------------
# Module: Cloud Run service
#------------------------------------------------------------------

module "run" {
  source = "../cloud-run"

  global_config = local.global
  run_config    = local.run_config

  depends_on = [module.gke]
}

#------------------------------------------------------------------
# Module: ArgoCD
#------------------------------------------------------------------

module "argocd" {
  source = "../argocd"

  global_config = local.global
  argocd_config = local.argocd_config

  depends_on = [module.gke]
}
