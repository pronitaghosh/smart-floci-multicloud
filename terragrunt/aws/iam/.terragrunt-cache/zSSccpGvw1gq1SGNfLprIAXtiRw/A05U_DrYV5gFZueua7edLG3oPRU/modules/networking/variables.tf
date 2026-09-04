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
# Network Configuration
#------------------------------------------------------------------

variable "network_config" {
  type = object({
    name                 = string
    cidr                 = string
    enable_dns_support   = optional(bool, true)
    enable_dns_hostnames = optional(bool, true)

    subnets = list(object({
      name              = string
      cidr              = string
      availability_zone = string
      type              = string # "public" | "private"
      tags              = optional(map(string), {})
    }))

    security_groups = optional(list(object({
      name        = string
      description = optional(string, "Managed by Terraform")
      ingress = optional(list(object({
        description = optional(string, "")
        from_port   = number
        to_port     = number
        protocol    = string
        cidr_blocks = list(string)
      })), [])
      tags = optional(map(string), {})
    })), [])

    tags = optional(map(string), {})
  })

  description = "VPC, subnets, routing and shared security groups"
}
