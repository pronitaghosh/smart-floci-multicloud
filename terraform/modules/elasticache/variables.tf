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
# ElastiCache Configuration
#------------------------------------------------------------------

variable "elasticache_config" {
  type = list(object({
    name               = string
    engine             = optional(string, "redis")
    node_type          = optional(string, "cache.t3.micro")
    num_cache_clusters = optional(number, 1)
    port               = optional(number, 6379)
    description        = optional(string, "Managed by Terraform")

    subnet_ids         = optional(list(string), [])
    security_group_ids = optional(list(string), [])

    # floci returns UnsupportedOperation for CreateCacheSubnetGroup. Real AWS
    # requires one for a VPC cache, so this defaults to true.
    create_subnet_group = optional(bool, true)

    tags = optional(map(string), {})
  }))

  description = "ElastiCache replication groups"
  default     = []
}
