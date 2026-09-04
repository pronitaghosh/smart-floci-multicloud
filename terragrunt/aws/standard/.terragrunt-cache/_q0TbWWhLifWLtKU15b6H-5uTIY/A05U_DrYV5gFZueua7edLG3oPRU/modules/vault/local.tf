#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------

locals {
  clusters = { for v in var.vault_config : v.name => v }

  # Vault's awskms seal reads credentials and endpoint from the environment.
  # floci accepts any credentials, so the values are the usual throwaways.
  seal_env = {
    AWS_ACCESS_KEY_ID     = "test"
    AWS_SECRET_ACCESS_KEY = "test"
  }
}
