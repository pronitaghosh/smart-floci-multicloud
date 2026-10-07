#------------------------------------------------------------------
# Module: SQL
#------------------------------------------------------------------

module "sql" {
  source = "../sql"

  global_config = local.global
  sql_config    = local.sql_config
}

#------------------------------------------------------------------
# Module: Firestore (placeholder, SDK-provisioned)
#------------------------------------------------------------------

module "firestore" {
  source = "../firestore"

  global_config    = local.global
  firestore_config = local.firestore_config
}

#------------------------------------------------------------------
# Module: PubSub
#------------------------------------------------------------------

module "pubsub" {
  source = "../pubsub"

  global_config = local.global
  pubsub_config = local.pubsub_config
}

#------------------------------------------------------------------
# Module: Secrets
#------------------------------------------------------------------

module "secrets" {
  source = "../secrets"

  global_config  = local.global
  secrets_config = local.secrets_config
}
