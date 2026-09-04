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
    "${include.env.locals.tf_local_module_path}//modules${local.submodule}"
    ) : (
    "tfr://${include.env.locals.tf_module_repo}${local.submodule}?version=${include.env.locals.tf_module_version}"
  )
}

# ------------------------------------------------------------------
# Upstream stacks
# ------------------------------------------------------------------
# The reference house style uses skip_outputs = true and resolves everything
# through a Vault-sourced config. Here the values come straight from the
# upstream state instead, which is plainer Terragrunt and needs no
# preprocessing step. mock_outputs keep `plan` working before a first apply.
# ------------------------------------------------------------------

dependency "bootstrap" {
  config_path = "../bootstrap"

  # Merge mocks over real state. Without this, adding an output to an upstream
  # stack breaks `plan` here until that stack is re-applied -- mock_outputs
  # alone only apply when NO outputs can be read.
  mock_outputs_merge_strategy_with_state  = "shallow"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    private_subnet_ids = ["subnet-mock-a", "subnet-mock-b"]
    security_group_ids = { shared = "sg-mock", redis = "sg-mock", alb = "sg-mock" }
    kms_key_arns       = { key = "arn:aws:kms:us-east-1:000000000000:key/mock" }
  }
}

dependency "iam" {
  config_path  = "../iam"
  skip_outputs = true
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
# that four separate states exist.
# ------------------------------------------------------------------

inputs = {
  config = yamlencode(merge(
    local.merged_config_hcl,
    {
      resolved = {
        private_subnet_ids = dependency.bootstrap.outputs.private_subnet_ids
        security_group_ids = dependency.bootstrap.outputs.security_group_ids
        kms_key_arns       = dependency.bootstrap.outputs.kms_key_arns
      }
    }
  ))
}
