#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------

locals {
  config = yamldecode(var.config)
  global = local.config.global

  # --------------------------------------------------------------
  # Networking
  # --------------------------------------------------------------
  network_config = try(local.config.network, null)

  # --------------------------------------------------------------
  # KMS
  # --------------------------------------------------------------
  kms_config = try(local.config.kms_keys, [])

  # --------------------------------------------------------------
  # ECR
  # --------------------------------------------------------------
  ecr_config = try(local.config.ecr_repositories, [])

  # --------------------------------------------------------------
  # S3 -- the KMS key is resolved by name from the key created above, so the
  # YAML refers to "key" rather than repeating an ARN.
  # --------------------------------------------------------------
  s3_config = [
    for b in try(local.config.buckets, []) : merge(b, {
      encrypt     = try(b.kms_key_name, null) != null
      kms_key_arn = try(module.kms_key.key_arns[b.kms_key_name], null)
    })
  ]

  # --------------------------------------------------------------
  # ACM
  # --------------------------------------------------------------
  acm_config = try(local.config.acm_certificates, [])

  # --------------------------------------------------------------
  # SSM parameters owned by this stack. ECR repository URLs are only known
  # here, so /<client>/ecr/* belongs to bootstrap rather than standard.
  # --------------------------------------------------------------
  ssm_config = concat(
    [{
      name  = "/${local.global.client_name}/environment"
      value = local.global.environment
    }],
    [
      for name, url in module.ecr_repository.repository_urls : {
        name  = "/${local.global.client_name}/ecr/${name}"
        value = url
      }
    ]
  )
}
