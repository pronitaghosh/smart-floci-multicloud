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
# CloudFront Configuration
#------------------------------------------------------------------

variable "cloudfront_config" {
  type = list(object({
    name                        = string
    bucket_id                   = string
    bucket_regional_domain_name = string
    acm_certificate_arn         = optional(string, null)
    aliases                     = optional(list(string), [])
    default_root_object         = optional(string, "index.html")
    comment                     = optional(string, "Managed by Terraform")
    tags                        = optional(map(string), {})
  }))

  description = "CloudFront distributions. Disabled against floci -- see docs/floci-gaps.md"
  default     = []
}
