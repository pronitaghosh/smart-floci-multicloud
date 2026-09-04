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
# KMS Configuration
#------------------------------------------------------------------

variable "kms_config" {
  type = list(object({
    name                    = string
    description             = optional(string, "Managed by Terraform")
    deletion_window_in_days = optional(number, 7)
    enable_key_rotation     = optional(bool, true)
    tags                    = optional(map(string), {})
  }))

  description = "Customer-managed KMS keys and their aliases"
  default     = []
}
