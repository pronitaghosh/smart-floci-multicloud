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
