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
# EKS Configuration
#------------------------------------------------------------------

variable "eks_config" {
  type = list(object({
    name               = string
    kubernetes_version = optional(string, "1.29")
    cluster_role_arn   = string
    subnet_ids         = list(string)

    node_groups = optional(list(object({
      name           = string
      node_role_arn  = string
      instance_types = optional(list(string), ["t3.medium"])
      desired_size   = optional(number, 2)
      min_size       = optional(number, 1)
      max_size       = optional(number, 3)
      subnet_ids     = optional(list(string), null)
      tags           = optional(map(string), {})
    })), [])

    tags = optional(map(string), {})
  }))

  description = "EKS clusters and their managed node groups"
  default     = []
}
