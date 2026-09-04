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
# Secrets Manager Configuration
#------------------------------------------------------------------

variable "secrets_config" {
  type = list(object({
    name        = string
    description = optional(string, "Managed by Terraform")
    kms_key_arn = optional(string, null)

    # Rendered to JSON as the secret value. Values are already-resolved
    # strings -- this module does no lookups of its own.
    values = map(string)

    recovery_window_in_days = optional(number, 0)
    tags                    = optional(map(string), {})
  }))

  description = "Secrets Manager secrets and their JSON payloads"
  default     = []
}
