# This file is overwritten by Terragrunt at each run of the composite module.

# -----------------------------------------------------------------------------
# Module: Cross-account / aliased-provider resources
# -----------------------------------------------------------------------------
# Terragrunt generates module blocks here for anything needing a non-default
# provider alias, because a provider alias cannot be selected dynamically from
# within Terraform. See terragrunt/aws/bootstrap/dynamic_modules.tftpl.
#
# Example of a generated block:
#
# module "dns_cross_account" {
#   source        = "../dns"
#   global_config = local.global
#   dns_config    = local.dns_config["shared"]
#   providers = {
#     aws = aws.ops
#   }
# }
