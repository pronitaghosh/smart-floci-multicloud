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

  # Static kubeconfig context for the provider blocks below. Matches the
  # context written by scripts/fix-kubeconfig-gcp.sh.
  k8s_context = "floci-gcp-${try(local.merged_config_hcl.clusters[0].name, "smartcloud-cluster")}"
}

# ------------------------------------------------------------------
# Upstream stacks
# ------------------------------------------------------------------
# Mocks keep `plan` working before upstream apply.
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

  # Dummy context so plan works before the kubeconfig script has run. The
  # real context replaces it; providers only read it at apply time.
  before_hook "ensure_kubeconfig" {
    commands = ["plan", "apply", "validate"]
    execute  = ["bash", "-c", "mkdir -p ~/.kube; touch ~/.kube/config; if ! kubectl config get-contexts \"${local.k8s_context}\" >/dev/null 2>&1; then kubectl config set-cluster dummy --server=https://127.0.0.1:65534 --insecure-skip-tls-verify=true >/dev/null 2>&1 || true; kubectl config set-credentials dummy --token=fake >/dev/null 2>&1 || true; kubectl config set-context \"${local.k8s_context}\" --cluster=dummy --user=dummy >/dev/null 2>&1 || true; fi"]
  }

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
# Kubernetes providers
# ------------------------------------------------------------------
# Providers are configured BEFORE any resource is created, so they cannot
# read the endpoint of a cluster this same stack is about to build. Reading
# a static kubeconfig context instead keeps the configuration plan-safe.
# The context is written by scripts/fix-kubeconfig-gcp.sh, which extracts
# the k3s admin config from the emulator sidecar (client-cert auth, no
# get-credentials flow). Cold-start sequence mirrors AWS:
#   targeted cluster apply, then kubeconfig script, then full apply.
# ------------------------------------------------------------------

generate "k8s_providers" {
  path      = "tg-gen-k8s-providers.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-EOF
    provider "kubernetes" {
      config_path    = pathexpand("~/.kube/config")
      config_context = "${local.k8s_context}"
    }

    provider "helm" {
      kubernetes {
        config_path    = pathexpand("~/.kube/config")
        config_context = "${local.k8s_context}"
      }
    }
  EOF
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
