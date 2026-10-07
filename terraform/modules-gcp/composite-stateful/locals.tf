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

  # Values resolved by earlier stacks, folded into the YAML under `resolved:`
  # by the stateful leaf config. No cross-stack remote state.
  resolved = try(local.config.resolved, {})

  # floci does not round-trip every field. See global.floci_compat.
  floci_compat = try(local.global.floci_compat, false)

  # --------------------------------------------------------------
  # SQL -- private_network stays null locally; real GCP wires the VPC
  # behind the compat flag.
  # --------------------------------------------------------------
  sql_config = [
    for i in try(local.config.sql_instances, []) : merge(i, {
      private_network = local.floci_compat ? null : try(i.private_network, null)
    })
  ]

  # --------------------------------------------------------------
  # Firestore -- SDK-provisioned placeholder
  # --------------------------------------------------------------
  firestore_config = try(local.config.firestore_databases, [])

  # --------------------------------------------------------------
  # PubSub
  # --------------------------------------------------------------
  pubsub_config = {
    topics        = try(local.config.pubsub_topics, [])
    subscriptions = try(local.config.pubsub_subscriptions, [])
  }

  # --------------------------------------------------------------
  # Secrets -- values assembled here from this stack's own outputs, so the
  # secret module itself performs no lookups.
  # --------------------------------------------------------------
  db = try(local.config.sql_instances[0], null)

  app_secret_values = local.db == null ? {} : {
    db_username = local.db.username
    db_password = local.db.password
    db_host     = try(module.sql.connection_names[local.db.name], "")
    db_name     = local.db.database_name
  }

  secrets_config = [
    for s in try(local.config.secrets, []) : merge(s, {
      values = s.name == "smartcloud-app-credentials" ? local.app_secret_values : try(s.values, {})
    })
  ]
}

#------------------------------------------------------------------
# Guardrails
#------------------------------------------------------------------
# The bundled demo password must never reach real GCP. floci runs entirely
# on localhost, so a non-local endpoint plus the demo credential is a mistake.
#------------------------------------------------------------------

check "demo_password_stays_local" {
  assert {
    condition = local.db == null || try(local.db.password, "") != "LocalDemoPass123!" || can(regex(
      "localhost|127\\.0\\.0\\.1", try(local.config.global.endpoint_url, "localhost")
    ))
    error_message = "The built-in demo DB password is set but the target is not local. Set a real secret before applying against anything other than floci-gcp."
  }
}
