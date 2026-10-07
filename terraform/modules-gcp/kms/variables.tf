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
# KMS Configuration
#------------------------------------------------------------------

variable "kms_config" {
  type = list(object({
    name            = string
    description     = optional(string, "Managed by Terraform")
    rotation_period = optional(string, "7776000s")
    labels                     = optional(map(string), {})
  }))

  description = "KMS key rings and crypto keys"
  default     = []
}
