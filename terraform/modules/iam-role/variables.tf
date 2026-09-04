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
# IAM Configuration
#------------------------------------------------------------------

variable "iam_config" {
  type = list(object({
    name            = string
    trusted_service = string
    description     = optional(string, "Managed by Terraform")

    managed_policy_arns = optional(list(string), [])

    inline_policies = optional(list(object({
      name = string
      statements = list(object({
        effect    = optional(string, "Allow")
        actions   = list(string)
        resources = optional(list(string), ["*"])
      }))
    })), [])

    tags = optional(map(string), {})
  }))

  description = "IAM roles, their trust relationships and attached policies"
  default     = []
}
