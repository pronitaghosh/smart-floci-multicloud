include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "env" {
  path   = "${get_terragrunt_dir()}/../_env/env.hcl"
  expose = true
}

locals {
  merged_config     = include.root.locals.merged_config
  merged_config_hcl = include.root.locals.merged_config_hcl

  # The directory name IS the composite name. Adding a stack is `mkdir`.
  submodule   = "/composite-${basename(get_terragrunt_dir())}"
  tfplan_path = "${get_terragrunt_dir()}/.tfplan/"

  module_source = include.env.locals.tf_local_module == "true" ? (
    "${include.env.locals.tf_local_module_path}//modules-gcp${local.submodule}"
    ) : (
    "tfr://${include.env.locals.tf_module_repo}${local.submodule}?version=${include.env.locals.tf_module_version}"
  )
}

# ------------------------------------------------------------------
# Upstream stacks
# ------------------------------------------------------------------
# ArgoCD deferred to Block 6; no IAM/KMS wiring needed here. Mocks keep
# `plan` working before upstream apply.
# ------------------------------------------------------------------

dependency "bootstrap" {
  config_path = "../bootstrap"

  mock_outputs_merge_strategy_with_state  = "shallow"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    network_id = "projects/floci-local/global/networks/smartcloud"
  }
}

dependency "stateful" {
  config_path = "../stateful"

  mock_outputs_merge_strategy_with_state  = "shallow"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    sql_connection_names = { postgres = "floci-local:us-central1:postgres" }
  }
}

terraform {
  source = local.module_source

  # Stash the plan so `plan` and `apply` can be separate CI jobs.
  before_hook "before_copy_tfplan" {
    commands = ["apply"]
    execute  = ["bash", "-c", "cp ${local.tfplan_path}/.${basename(get_terragrunt_dir())}.tfplan . 2>/dev/null || :"]
  }

  after_hook "after_copy_tfplan" {
    commands = ["plan"]
    execute  = ["bash", "-c", "mkdir -p ${local.tfplan_path} && cp .${basename(get_terragrunt_dir())}.tfplan ${local.tfplan_path} 2>/dev/null || :"]
  }
}

# ------------------------------------------------------------------
# Inputs
# ------------------------------------------------------------------
# The composite still takes exactly one variable. Upstream values are folded
# into the same YAML document under `resolved:`, so the module never learns
# that separate states exist.
# ------------------------------------------------------------------

inputs = {
  config = yamlencode(merge(
    local.merged_config_hcl,
    {
      resolved = {
        network_id           = dependency.bootstrap.outputs.network_id
        sql_connection_names = dependency.stateful.outputs.sql_connection_names
      }
    }
  ))
}
