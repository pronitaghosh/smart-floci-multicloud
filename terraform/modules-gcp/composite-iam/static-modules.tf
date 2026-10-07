#------------------------------------------------------------------
# Module: IAM
#------------------------------------------------------------------
# Pod access mechanism: project bindings are created here but never enforced
# locally (emulator accepts any token). Documented emulator bypass covers
# local mode; the same bindings govern real GCP with the compat flag off.
#------------------------------------------------------------------

module "iam" {
  source = "../iam"

  global_config = local.global
  iam_config    = local.iam_config
}
