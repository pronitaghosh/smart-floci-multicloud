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

  cluster_name = try(local.merged_config_hcl.clusters[0].name, "")

  module_source = include.env.locals.tf_local_module == "true" ? (
    "${include.env.locals.tf_local_module_path}//modules${local.submodule}"
    ) : (
    "tfr://${include.env.locals.tf_module_repo}${local.submodule}?version=${include.env.locals.tf_module_version}"
  )
}

# ------------------------------------------------------------------
# Upstream stacks
# ------------------------------------------------------------------
# mock_outputs keep `plan` working before the upstream stacks have applied.
# ------------------------------------------------------------------

dependency "bootstrap" {
  config_path = "../bootstrap"

  # Merge mocks over real state. Without this, adding an output to an upstream
  # stack breaks `plan` here until that stack is re-applied -- mock_outputs
  # alone only apply when NO outputs can be read.
  mock_outputs_merge_strategy_with_state  = "shallow"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    vpc_id                       = "vpc-mock"
    all_subnet_ids               = ["subnet-mock-a", "subnet-mock-b"]
    public_subnet_ids            = ["subnet-mock-a", "subnet-mock-b"]
    security_group_ids           = { shared = "sg-mock", redis = "sg-mock", alb = "sg-mock" }
    acm_certificate_arns         = { alb = "arn:aws:acm:us-east-1:000000000000:certificate/mock" }
    bucket_regional_domain_names = { "smartcloud-frontend-static" = "mock.s3.us-east-1.amazonaws.com" }
  }
}

dependency "iam" {
  config_path = "../iam"

  # Merge mocks over real state. Without this, adding an output to an upstream
  # stack breaks `plan` here until that stack is re-applied -- mock_outputs
  # alone only apply when NO outputs can be read.
  mock_outputs_merge_strategy_with_state  = "shallow"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    role_arns = {
      "smartcloud-cluster-cluster-role" = "arn:aws:iam::000000000000:role/mock"
      "smartcloud-cluster-node-role"    = "arn:aws:iam::000000000000:role/mock"
    }
  }
}

dependency "stateful" {
  config_path = "../stateful"

  # Merge mocks over real state. Without this, adding an output to an upstream
  # stack breaks `plan` here until that stack is re-applied -- mock_outputs
  # alone only apply when NO outputs can be read.
  mock_outputs_merge_strategy_with_state  = "shallow"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    vault_unseal_key_ids       = { smartcloud = "mock-key-id" }
    vault_root_token_secrets   = { smartcloud = "smartcloud-vault-root-token" }
    vault_recovery_key_secrets = { smartcloud = "smartcloud-vault-recovery-keys" }
  }
}

# ------------------------------------------------------------------
# Modules requiring a non-default provider alias
# ------------------------------------------------------------------
# A provider alias cannot be selected dynamically inside Terraform, so the
# module block is generated instead. Generates nothing against floci, where
# floci_compat disables CloudFront.
# ------------------------------------------------------------------

generate "dynamic_modules" {
  path      = "dynamic_modules.tf"
  if_exists = "overwrite"

  contents = templatefile("${get_terragrunt_dir()}/dynamic_modules.tftpl", {
    cloudfront_distributions = try(local.merged_config_hcl.global.floci_compat, false) ? [] : [
      for d in try(local.merged_config_hcl.cloudfront_distributions, []) : d
      if try(d.certificate_name, null) != null
    ]
  })
}

# ------------------------------------------------------------------
# Kubernetes providers
# ------------------------------------------------------------------
# Providers are configured BEFORE any resource is created, so they cannot read
# the endpoint of a cluster this same stack is about to build. Reading the
# kubeconfig instead keeps the configuration static and plan-safe.
#
# The consequence: on a clean slate `make up` fails at
#   provider["registry.terraform.io/hashicorp/kubernetes"] context
#   "arn:aws:eks:us-east-1:000000000000:cluster/<name>" does not exist
# because `tg-gen-k8s-providers.tf` is evaluated before `module.eks_cluster`
# exists. The project handles it by cold-start sequence:
#   cd terragrunt/aws/standard
#   terragrunt apply -target=module.eks_cluster
#   make kubeconfig   # writes ~/.kube/config context
# then full apply. Splitting platform (Vault/ArgoCD) into its own stack is
# the usual way to avoid this; keeping it here trades that for one fewer stack.
#
# Auth is the ordinary EKS exec pattern, not an emulator special case: floci
# wires a token authentication webhook into the k3s apiserver, and
# `aws eks get-token` signs its STS request offline with no network call.
# ------------------------------------------------------------------

generate "k8s_providers" {
  path      = "tg-gen-k8s-providers.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-EOF
    provider "kubernetes" {
      config_path    = pathexpand("~/.kube/config")
      config_context = "arn:aws:eks:${include.env.locals.region}:000000000000:cluster/${local.cluster_name}"
    }

    provider "helm" {
      kubernetes {
        config_path    = pathexpand("~/.kube/config")
        config_context = "arn:aws:eks:${include.env.locals.region}:000000000000:cluster/${local.cluster_name}"
      }
    }
  EOF
}

terraform {
  source = local.module_source

  before_hook "ensure_kubeconfig" {
    commands = ["plan", "apply", "validate"]
    execute  = ["bash", "-c", "mkdir -p ~/.kube; touch ~/.kube/config; if ! kubectl config get-contexts \"arn:aws:eks:${include.env.locals.region}:000000000000:cluster/${local.cluster_name}\" >/dev/null 2>&1; then kubectl config set-cluster dummy --server=https://127.0.0.1:65534 --insecure-skip-tls-verify=true >/dev/null 2>&1 || true; kubectl config set-credentials dummy --exec-api-version=client.authentication.k8s.io/v1beta1 --exec-command=aws --exec-arg=eks --exec-arg=get-token --exec-arg=--cluster-name --exec-arg=${local.cluster_name} --exec-arg=--region --exec-arg=${include.env.locals.region} >/dev/null 2>&1 || true; kubectl config set-context \"arn:aws:eks:${include.env.locals.region}:000000000000:cluster/${local.cluster_name}\" --cluster=dummy --user=dummy >/dev/null 2>&1 || true; fi"]
  }

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
        vpc_id                       = dependency.bootstrap.outputs.vpc_id
        all_subnet_ids               = dependency.bootstrap.outputs.all_subnet_ids
        public_subnet_ids            = dependency.bootstrap.outputs.public_subnet_ids
        security_group_ids           = dependency.bootstrap.outputs.security_group_ids
        acm_certificate_arns         = dependency.bootstrap.outputs.acm_certificate_arns
        bucket_regional_domain_names = dependency.bootstrap.outputs.bucket_regional_domain_names
        role_arns                    = dependency.iam.outputs.role_arns

        vault_unseal_key_ids       = dependency.stateful.outputs.vault_unseal_key_ids
        vault_root_token_secrets   = dependency.stateful.outputs.vault_root_token_secrets
        vault_recovery_key_secrets = dependency.stateful.outputs.vault_recovery_key_secrets
      }
    }
  ))
}
