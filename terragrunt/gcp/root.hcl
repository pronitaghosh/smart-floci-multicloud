#------------------------------------------------------------------
# Root configuration (GCP)
#------------------------------------------------------------------
# Included by every GCP stack. Owns two things the stacks must not repeat:
# where state lives, and how providers are configured.
#------------------------------------------------------------------

locals {
  env_file = "${get_parent_terragrunt_dir()}/_env/env.hcl"
  env      = read_terragrunt_config(local.env_file).locals

  # An empty endpoint means "real GCP". Anything else is treated as an
  # emulator and switches on custom endpoints plus the fake token.
  is_local = local.env.gcp_endpoint_url != ""

  # Secrets are substituted here rather than by a preprocessing step, so there
  # is no generated config file on disk and no extra tooling to install.
  merged_config = replace(
    replace(
      file("${get_parent_terragrunt_dir()}/_env/${local.env.config_file}"),
      "__DB_PASSWORD__",
      local.env.db_password,
    ),
    "__FLOCI_IP__",
    local.env.gcp_in_cluster,
  )

  merged_config_hcl = try(yamldecode(local.merged_config), {})
}

#------------------------------------------------------------------
# Remote state
#------------------------------------------------------------------
# Local backend, one file per stack under a gcp subtree separate from AWS.
# Switching environment is `export ENVIRONMENT_NAME=staging` and nothing else.
#------------------------------------------------------------------

remote_state {
  backend = "local"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    path = "${get_parent_terragrunt_dir()}/../../.state/${local.env.environment_name}/gcp/${path_relative_to_include()}/terraform.tfstate"
  }
}

#------------------------------------------------------------------
# Providers
#------------------------------------------------------------------
# Code-generated into every stack. This is what lets one module tree target
# both floci-gcp and real GCP: the modules stay identical and know nothing
# about an emulator -- only this generated file differs.
#------------------------------------------------------------------

generate "providers" {
  path      = "tg-gen-providers.tf"
  if_exists = "overwrite_terragrunt"

  contents = templatefile("${get_parent_terragrunt_dir()}/provider-gcp.tftpl", {
    project      = local.env.project
    region       = local.env.region
    endpoint_url = local.env.gcp_endpoint_url
  })
}

#------------------------------------------------------------------
# Shared inputs
#------------------------------------------------------------------

inputs = {
  config = local.merged_config
}
