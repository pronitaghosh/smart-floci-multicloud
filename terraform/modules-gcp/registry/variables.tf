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
# Registry Configuration
#------------------------------------------------------------------

variable "registry_config" {
  type = list(object({
    name   = string
    labels = optional(map(string), {})
  }))

  description = "Artifact Registry Docker repositories, one per service image"
  default     = []
}
