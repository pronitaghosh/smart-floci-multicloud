#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------

locals {
  config = yamldecode(var.config)
  global = local.config.global

  # Values resolved by earlier stacks, injected into the merged config by
  # terragrunt/_scripts/merge-config.py. Keeps stacks decoupled: no
  # cross-stack terraform_remote_state and no dependency outputs.
  resolved = try(local.config.resolved, {})

  # floci cannot round-trip a few attributes. See global.floci_compat.
  floci_compat = try(local.global.floci_compat, false)

  # --------------------------------------------------------------
  # RDS
  # --------------------------------------------------------------
  rds_config = [
    for i in try(local.config.rds_instances, []) : merge(i, {
      subnet_ids             = try(local.resolved.private_subnet_ids, [])
      vpc_security_group_ids = compact([try(local.resolved.security_group_ids.shared, "")])
      # floci reads storage_encrypted and kms_key_id back as unset regardless
      # of what is sent, and both force replacement -- so every plan would
      # destroy and recreate the database. null leaves the provider treating
      # them as computed, which removes the drift entirely. Real AWS keeps
      # both fully managed.
      storage_encrypted = local.floci_compat ? null : try(i.storage_encrypted, null)
      kms_key_arn = local.floci_compat ? null : (
        try(i.kms_key_name, null) == null ? null : try(local.resolved.kms_key_arns[i.kms_key_name], null)
      )
    })
  ]

  # --------------------------------------------------------------
  # ElastiCache
  # --------------------------------------------------------------
  elasticache_config = [
    for c in try(local.config.elasticache_clusters, []) : merge(c, {
      subnet_ids         = try(local.resolved.private_subnet_ids, [])
      security_group_ids = compact([try(local.resolved.security_group_ids.redis, "")])

      # CreateCacheSubnetGroup returns UnsupportedOperation on floci. The
      # replication group itself works fine.
      create_subnet_group = local.floci_compat ? false : try(c.create_subnet_group, true)
    })
  ]

  # --------------------------------------------------------------
  # Secrets -- values are assembled here from this stack's own outputs, so the
  # secret module itself performs no lookups.
  # --------------------------------------------------------------
  db = try(local.config.rds_instances[0], null)

  app_secret_values = local.db == null ? {} : {
    db_username    = local.db.username
    db_password    = local.db.password
    db_endpoint    = try(module.rds.endpoints[local.db.name], "")
    db_name        = local.db.db_name
    redis_endpoint = try(values(module.elasticache.primary_endpoints)[0], "")
  }

  secrets_config = [
    for s in try(local.config.secrets, []) : merge(s, {
      values      = s.name == "${local.global.client_name}/app-credentials" ? local.app_secret_values : try(s.values, {})
      kms_key_arn = try(s.kms_key_name, null) == null ? null : try(local.resolved.kms_key_arns[s.kms_key_name], null)
    })
  ]
}

#------------------------------------------------------------------
# Guardrails
#------------------------------------------------------------------
# The bundled demo password must never reach a real AWS account. floci runs
# entirely on localhost, so a non-local endpoint plus the demo credential is
# always a mistake.
#------------------------------------------------------------------

check "demo_password_stays_local" {
  assert {
    condition = local.db == null || try(local.db.password, "") != "LocalDemoPass123!" || can(regex(
      "localhost|127\\.0\\.0\\.1", try(local.config.global.endpoint_url, "localhost")
    ))
    error_message = "The built-in demo DB password is set but the target is not local. Set a real secret before applying against anything other than floci."
  }
}
