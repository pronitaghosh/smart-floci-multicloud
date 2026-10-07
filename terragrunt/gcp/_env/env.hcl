#------------------------------------------------------------------
# Environment (GCP)
#------------------------------------------------------------------
# Everything is an env var with a working default. There are no
# per-environment directories: `ENVIRONMENT_NAME=staging make apply` is the
# whole story, and state separates itself by path.
#------------------------------------------------------------------

locals {
  #------------------------------------------------------------------
  # Identity
  #------------------------------------------------------------------
  client_name      = get_env("CLIENT_NAME", "smartcloud")
  environment_name = get_env("ENVIRONMENT_NAME", "dev")

  #------------------------------------------------------------------
  # Target
  #------------------------------------------------------------------
  project = get_env("TG_GCP_PROJECT", "floci-local")
  region  = get_env("TG_GCP_REGION", "us-central1")

  # Set to "" to target real GCP.
  gcp_endpoint_url = get_env("TG_GCP_ENDPOINT_URL", "http://localhost:4588")

  # In-cluster address of the emulator on the compose network.
  gcp_in_cluster = get_env("TG_GCP_IN_CLUSTER", "http://floci-gcp:4588")

  #------------------------------------------------------------------
  # Modules
  #------------------------------------------------------------------
  # Single repo, so local paths by default. Flipping TG_TF_LOCAL_MODULE to
  # false is what a two-repo split looks like: the live repo consumes the
  # module repo from a registry at a pinned version.
  tf_local_module      = get_env("TG_TF_LOCAL_MODULE", "true")
  tf_local_module_path = get_env("TG_TF_LOCAL_MODULE_PATH", "../../../terraform/modules-gcp")
  tf_module_repo       = get_env("TG_TF_MODULE_REPO", "registry.terraform.io/elokac/floci-gcp/gcp//modules")
  tf_module_version    = get_env("TG_TF_MODULE_VERSION", "0.1.0")

  #------------------------------------------------------------------
  # Config
  #------------------------------------------------------------------
  config_file = get_env("TG_TF_CONFIG_FILE", "config.yaml")

  # Substituted into the config at read time so no credential is ever written
  # to disk. The default is a throwaway for local floci runs only.
  db_password = get_env("TF_VAR_db_password", "LocalDemoPass123!")
}
