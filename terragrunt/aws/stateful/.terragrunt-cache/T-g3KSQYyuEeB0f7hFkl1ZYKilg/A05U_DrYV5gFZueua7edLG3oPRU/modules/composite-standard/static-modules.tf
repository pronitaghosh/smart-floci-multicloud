#------------------------------------------------------------------
# Module: EKS Cluster
#------------------------------------------------------------------

module "eks_cluster" {
  source = "../eks-cluster"

  global_config = local.global
  eks_config    = local.eks_config
}

#------------------------------------------------------------------
# Module: ALB
#------------------------------------------------------------------

module "alb" {
  source = "../alb"

  global_config = local.global
  alb_config    = local.alb_config
}

#------------------------------------------------------------------
# Module: CloudFront
#------------------------------------------------------------------

module "cloudfront" {
  source = "../cloudfront"

  global_config     = local.global
  cloudfront_config = local.cloudfront_config
}

#------------------------------------------------------------------
# Module: SSM Parameters
#------------------------------------------------------------------

module "ssm_parameters" {
  source = "../ssm-parameters"

  global_config = local.global
  ssm_config    = local.ssm_config
}

#------------------------------------------------------------------
# Module: Vault
#------------------------------------------------------------------
# Helm needs a cluster to install into, so these depend explicitly on the EKS
# module. The provider itself is configured from the kubeconfig -- see the
# note in terragrunt/aws/standard/terragrunt.hcl about cold starts.
#------------------------------------------------------------------

module "vault" {
  source = "../vault"

  global_config = local.global
  vault_config  = local.vault_config

  depends_on = [module.eks_cluster]
}

#------------------------------------------------------------------
# Module: ArgoCD
#------------------------------------------------------------------

module "argocd" {
  source = "../argocd"

  global_config = local.global
  argocd_config = local.argocd_config

  depends_on = [module.eks_cluster]
}
