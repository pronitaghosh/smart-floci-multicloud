#------------------------------------------------------------------
# Module: IAM Role
#------------------------------------------------------------------

module "iam_role" {
  source = "../iam-role"

  global_config = local.global
  iam_config    = local.iam_config
}
