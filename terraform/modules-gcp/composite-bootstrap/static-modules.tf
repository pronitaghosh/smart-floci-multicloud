#------------------------------------------------------------------
# Module: Networking
#------------------------------------------------------------------

module "networking" {
  source = "../network"

  global_config  = local.global
  network_config = local.network_config
}

#------------------------------------------------------------------
# Module: KMS
#------------------------------------------------------------------

module "kms" {
  source = "../kms"

  global_config = local.global
  kms_config    = local.kms_config
}

#------------------------------------------------------------------
# Module: Artifact Registry (placeholder outputs, Block 6 creates repos)
#------------------------------------------------------------------

module "registry" {
  source = "../registry"

  global_config   = local.global
  registry_config = local.registry_config
}

#------------------------------------------------------------------
# Module: Bucket
#------------------------------------------------------------------

module "bucket" {
  source = "../bucket"

  global_config = local.global
  bucket_config = local.bucket_config
}

#------------------------------------------------------------------
# Module: Project Services
#------------------------------------------------------------------

module "project_services" {
  source = "../project-services"

  global_config   = local.global
  services_config = local.services_config
}
