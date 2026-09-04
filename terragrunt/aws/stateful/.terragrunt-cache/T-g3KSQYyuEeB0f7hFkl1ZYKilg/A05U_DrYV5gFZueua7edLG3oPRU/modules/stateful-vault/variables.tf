#------------------------------------------------------------------
# Global Configuration
#------------------------------------------------------------------

variable "global_config" {
  type = object({
    client_name = string
    environment = string
    region      = string
    default_az  = string
    tags        = map(string)
  })

  description = "Global Configuration"
}

#------------------------------------------------------------------
# Vault Static Resources
#------------------------------------------------------------------

variable "vault_static_config" {
  type = list(object({
    name = string

    # Auto-unseal key. Vault calls kms:Encrypt/Decrypt on every seal and
    # unseal, so this is a genuine exercise of the emulated KMS rather than a
    # resource that merely gets created.
    unseal_key_deletion_window = optional(number, 7)

    # Created empty here; vault-init writes the real values with
    # put-secret-value so no token is ever recorded in terraform state.
    store_root_token    = optional(bool, true)
    store_recovery_keys = optional(bool, true)

    tags = optional(map(string), {})
  }))

  description = "Per-cluster AWS-side prerequisites for Vault: unseal key and secret containers"
  default     = []
}
