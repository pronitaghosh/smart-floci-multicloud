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
# Project Services Configuration
#------------------------------------------------------------------

variable "services_config" {
  type    = list(string)
  default = []

  description = "GCP APIs enabled on the project via Service Usage"
}
