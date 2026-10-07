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
# IAM Configuration
#------------------------------------------------------------------

variable "iam_config" {
  type = object({
    service_accounts = optional(list(object({
      name        = string
      description = optional(string, "Managed by Terraform")
    })), [])
    bindings = optional(list(object({
      account = string
      roles   = list(string)
    })), [])
  })

  description = "Service accounts and their project role bindings"
  default     = {}
}
