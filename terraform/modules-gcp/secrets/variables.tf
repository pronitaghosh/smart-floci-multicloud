#------------------------------------------------------------------
# Global Configuration (GCP)
#------------------------------------------------------------------

variable "global_config" {
  type = object({
    client_name = string
    environment = string
    project     = string
    region      = string
    labels      = map(string)
  })

  description = "Global Configuration"
}

#------------------------------------------------------------------
# Secrets Configuration
#------------------------------------------------------------------

variable "secrets_config" {
  type = list(object({
    name        = string
    description = optional(string, "Managed by Terraform")
    values      = optional(map(string), {})
    labels      = optional(map(string), {})
  }))

  description = "Secret Manager secrets with assembled values"
  default     = []
}
