#------------------------------------------------------------------
# Root configuration
#------------------------------------------------------------------
# Included by every stack. Owns two things the stacks must not repeat:
# where state lives, and how providers are configured.
#------------------------------------------------------------------

locals {
  env_file = "${get_parent_terragrunt_dir()}/_env/env.hcl"
  env      = read_terragrunt_config(local.env_file).locals

  # An empty endpoint means "real AWS". Anything else is treated as an
  # emulator and switches on endpoint overrides, path-style S3 and the
  # credential skips.
  is_local = local.env.aws_endpoint_url != ""

  # Secrets are substituted here rather than by a preprocessing step, so there
  # is no generated config file on disk and no extra tooling to install.
  merged_config = replace(
    replace(
      file("${get_parent_terragrunt_dir()}/_env/${local.env.config_file}"),
      "__DB_PASSWORD__",
      local.env.db_password,
    ),
    "__FLOCI_IP__",
    local.env.floci_in_cluster,
  )

  merged_config_hcl = try(yamldecode(local.merged_config), {})

  # floci multiplexes every service onto its single :4566 gateway.
  endpoint_services = local.is_local ? [
    "acm", "cloudfront", "cloudwatch", "dynamodb", "ec2", "ecr", "eks",
    "elasticache", "elbv2", "iam", "kms", "logs", "rds", "s3",
    "secretsmanager", "ssm", "sts",
  ] : []
}

#------------------------------------------------------------------
# Remote state
#------------------------------------------------------------------
# Local backend, one file per stack. State separation is by key path, not by
# directory tree -- switching environment is `export ENVIRONMENT_NAME=staging`
# and nothing else.
#------------------------------------------------------------------

remote_state {
  backend = "local"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    path = "${get_parent_terragrunt_dir()}/../../.state/${local.env.environment_name}/${path_relative_to_include()}/terraform.tfstate"
  }
}

#------------------------------------------------------------------
# Providers
#------------------------------------------------------------------
# Code-generated into every stack. This is what lets one module tree target
# both floci and real AWS: the modules stay identical and know nothing about
# an emulator -- only this generated file differs.
#------------------------------------------------------------------

generate "providers" {
  path      = "tg-gen-providers.tf"
  if_exists = "overwrite_terragrunt"

  contents = templatefile("${get_parent_terragrunt_dir()}/provider-aws.tftpl", {
    region            = local.env.region
    access_key        = local.env.aws_access_key
    secret_key        = local.env.aws_secret_key
    endpoint_url      = local.env.aws_endpoint_url
    endpoint_services = local.endpoint_services
    provider_aliases  = try(local.merged_config_hcl.global.provider_aliases, {})
    cluster_name      = try(local.merged_config_hcl.clusters[0].name, "")
  })
}

#------------------------------------------------------------------
# Shared inputs
#------------------------------------------------------------------

inputs = {
  config = local.merged_config
}
