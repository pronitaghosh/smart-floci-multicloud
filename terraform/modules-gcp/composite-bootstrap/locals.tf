#------------------------------------------------------------------
# Locals
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

  # --------------------------------------------------------------
  # Networking
  # --------------------------------------------------------------
  network_config = try(local.config.network, null)

  # --------------------------------------------------------------
  # KMS
  # --------------------------------------------------------------
  kms_config = try(local.config.kms_keys, [])

  # --------------------------------------------------------------
  # Artifact Registry -- placeholder addresses until the Block 6 flow
  # --------------------------------------------------------------
  registry_config = try(local.config.artifact_registry_repositories, [])

  # --------------------------------------------------------------
  # GCS
  # --------------------------------------------------------------
  bucket_config = try(local.config.buckets, [])

  # --------------------------------------------------------------
  # Project services
  # --------------------------------------------------------------
  services_config = try(local.config.project_services, [])
}
