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
# RDS Configuration
#------------------------------------------------------------------

variable "rds_config" {
  type = list(object({
    name              = string
    engine            = optional(string, "postgres")
    engine_version    = optional(string, "16")
    instance_class    = optional(string, "db.t3.micro")
    allocated_storage = optional(number, 20)
    db_name           = string
    username          = string
    password          = string

    subnet_ids             = list(string)
    vpc_security_group_ids = optional(list(string), [])

    # floci reads storage_encrypted and kms_key_id back as unset regardless of
    # what was sent, and both force replacement -- so every plan would destroy
    # and recreate the database. Passing null leaves the provider treating them
    # as computed, which removes the drift. Real AWS is unaffected: set them
    # and encryption stays fully managed.
    storage_encrypted = optional(bool, null)
    kms_key_arn       = optional(string, null)

    skip_final_snapshot = optional(bool, true)
    publicly_accessible = optional(bool, false)

    subnet_group_name = optional(string, null)
    tags              = optional(map(string), {})
  }))

  description = "RDS instances and their subnet groups"
  default     = []
}
