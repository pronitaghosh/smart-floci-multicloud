#------------------------------------------------------------------
# Module: RDS
#------------------------------------------------------------------

module "rds" {
  source = "../rds"

  global_config = local.global
  rds_config    = local.rds_config
}

#------------------------------------------------------------------
# Module: ElastiCache
#------------------------------------------------------------------

module "elasticache" {
  source = "../elasticache"

  global_config      = local.global
  elasticache_config = local.elasticache_config
}

#------------------------------------------------------------------
# Module: Secrets Manager
#------------------------------------------------------------------

module "secrets_manager" {
  source = "../secrets-manager"

  global_config  = local.global
  secrets_config = local.secrets_config
}
