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
# S3 Configuration
#------------------------------------------------------------------

variable "s3_config" {
  type = list(object({
    name       = string
    versioning = optional(string, "Enabled")

    # encrypt is the plan-time-known switch; kms_key_arn carries the value,
    # which is only resolved after the KMS module applies. Filtering on the
    # ARN would make the for_each keys unknown at plan time.
    encrypt     = optional(bool, false)
    kms_key_arn = optional(string, null)

    block_public_access = optional(bool, true)

    # Grants CloudFront (via OAC) read access. Harmless when no distribution
    # exists -- the principal simply never calls.
    allow_cloudfront_read = optional(bool, false)

    tags = optional(map(string), {})
  }))

  description = "S3 buckets and their encryption/access posture"
  default     = []
}
