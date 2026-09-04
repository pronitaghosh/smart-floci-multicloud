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
# ECR Configuration
#------------------------------------------------------------------

variable "ecr_config" {
  type = list(object({
    name                 = string
    image_tag_mutability = optional(string, "MUTABLE")
    scan_on_push         = optional(bool, false)
    force_delete         = optional(bool, true)
    tags                 = optional(map(string), {})
  }))

  description = "ECR repositories, one per service image"
  default     = []
}
