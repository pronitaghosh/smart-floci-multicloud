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
# GKE Configuration
#------------------------------------------------------------------

variable "gke_config" {
  type = list(object({
    name     = string
    location = optional(string, null)
    node_pools = optional(list(object({
      name         = string
      node_count   = optional(number, 2)
      machine_type = optional(string, "e2-medium")
    })), [])
    labels = optional(map(string), {})
  }))

  description = "GKE clusters and node pools"
  default     = []
}
