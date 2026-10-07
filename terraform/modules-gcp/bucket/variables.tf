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
# Bucket Configuration
#------------------------------------------------------------------

variable "bucket_config" {
  type = list(object({
    name                      = string
    versioning                = optional(bool, true)
    public_access_prevention  = optional(string, "enforced")
    uniform_bucket_level_access = optional(bool, true)
    lifecycle_age_days        = optional(number, null)
    labels                    = optional(map(string), {})
  }))

  description = "GCS buckets and their versioning/access posture"
  default     = []
}
