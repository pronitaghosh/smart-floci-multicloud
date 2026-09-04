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
# ACM Configuration
#------------------------------------------------------------------

variable "acm_config" {
  type = list(object({
    name              = string
    domain_name       = string
    validation_method = optional(string, "DNS")
    tags              = optional(map(string), {})
  }))

  description = "ACM certificates"
  default     = []
}
