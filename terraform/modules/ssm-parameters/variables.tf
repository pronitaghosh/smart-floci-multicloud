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
# SSM Parameter Configuration
#------------------------------------------------------------------

variable "ssm_config" {
  type = list(object({
    name   = string
    value  = string
    type   = optional(string, "String")
    create = optional(bool, true)
    tags   = optional(map(string), {})
  }))

  description = "SSM parameters. Names are absolute paths, e.g. /msdemo/gateway_url"
  default     = []
}
