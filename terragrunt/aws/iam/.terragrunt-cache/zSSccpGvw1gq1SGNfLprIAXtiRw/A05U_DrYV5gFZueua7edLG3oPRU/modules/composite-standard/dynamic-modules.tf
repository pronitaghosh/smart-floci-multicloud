# This file is overwritten by Terragrunt at each run of the composite module.

# -----------------------------------------------------------------------------
# Module: CloudFront ACM certificate (us-east-1)
# -----------------------------------------------------------------------------
# Real CloudFront requires its certificate in us-east-1 regardless of where the
# rest of the stack lives, which means a second aws provider alias. A provider
# alias cannot be chosen dynamically inside Terraform, so Terragrunt generates
# one module block per distribution from
# terragrunt/aws/standard/dynamic_modules.tftpl.
#
# Nothing is generated against floci, because the overlay disables CloudFront.
#
# Example of a generated block:
#
# module "cloudfront_cert_frontend" {
#   source        = "../acm-certificate"
#   global_config = local.global
#   acm_config    = [local.cloudfront_certificates["frontend"]]
#   providers = {
#     aws = aws.us_east_1
#   }
# }
