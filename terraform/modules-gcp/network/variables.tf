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
# Network Configuration
#------------------------------------------------------------------

variable "network_config" {
  type = object({
    name                     = string
    auto_create_subnetworks  = optional(bool, false)
    subnets = list(object({
      name   = string
      cidr   = string
      region = string
    }))
    firewall_rules = optional(list(object({
      name          = string
      description   = optional(string, "Managed by Terraform")
      source_ranges = list(string)
    })), [])

    labels = optional(map(string), {})
  })

  description = "VPC network, subnetworks and shape-only firewall rules"
}
