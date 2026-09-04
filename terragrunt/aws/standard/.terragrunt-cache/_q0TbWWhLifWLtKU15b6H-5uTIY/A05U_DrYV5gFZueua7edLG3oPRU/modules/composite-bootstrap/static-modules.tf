#------------------------------------------------------------------
# Module: Networking
#------------------------------------------------------------------

module "networking" {
  source = "../networking"

  global_config  = local.global
  network_config = local.network_config
}

#------------------------------------------------------------------
# Module: KMS Key
#------------------------------------------------------------------

module "kms_key" {
  source = "../kms-key"

  global_config = local.global
  kms_config    = local.kms_config
}

#------------------------------------------------------------------
# Module: ECR Repository
#------------------------------------------------------------------

module "ecr_repository" {
  source = "../ecr-repository"

  global_config = local.global
  ecr_config    = local.ecr_config
}

#------------------------------------------------------------------
# Module: S3 Buckets
#------------------------------------------------------------------

module "s3_buckets" {
  source = "../s3-buckets"

  global_config = local.global
  s3_config     = local.s3_config
}

#------------------------------------------------------------------
# Module: ACM Certificate
#------------------------------------------------------------------

module "acm_certificate" {
  source = "../acm-certificate"

  global_config = local.global
  acm_config    = local.acm_config
}

#------------------------------------------------------------------
# Module: SSM Parameters
#------------------------------------------------------------------

module "ssm_parameters" {
  source = "../ssm-parameters"

  global_config = local.global
  ssm_config    = local.ssm_config
}
