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
# Vault Runtime Configuration
#------------------------------------------------------------------

variable "vault_config" {
  type = list(object({
    name          = string
    namespace     = optional(string, "vault")
    chart_version = optional(string, "0.29.1")

    replicas = optional(number, 3)

    # Raft needs a PVC per replica. k3s ships local-path-provisioner (only
    # traefik is disabled), so this works on floci -- but set data_storage
    # false to fall back to emptyDir if PVCs do not bind.
    data_storage      = optional(bool, true)
    data_storage_size = optional(string, "1Gi")

    # awskms auto-unseal against the emulated KMS. Set false for Shamir, in
    # which case the unseal keys are written to Secrets Manager instead.
    auto_unseal   = optional(bool, true)
    unseal_key_id = optional(string, "")
    kms_endpoint  = optional(string, "")

    root_token_secret_name    = optional(string, "")
    recovery_keys_secret_name = optional(string, "")

    # Where the in-cluster pods reach the emulated AWS API. floci's own
    # address on the docker network, not localhost -- a pod's localhost is
    # its own loopback.
    aws_endpoint_url = optional(string, "http://172.18.0.2:4566")
    aws_region       = optional(string, "us-east-1")

    tags = optional(map(string), {})
  }))

  description = "Vault clusters deployed into Kubernetes"
  default     = []
}
