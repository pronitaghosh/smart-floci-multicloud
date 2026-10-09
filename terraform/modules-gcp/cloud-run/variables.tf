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
# Cloud Run Configuration
#------------------------------------------------------------------

variable "run_config" {
  type = list(object({
    name       = string
    image_name = optional(string, "")
    port       = optional(number, 8080)
    labels     = optional(map(string), {})
  }))

  description = "Cloud Run services"
  default     = []
}
