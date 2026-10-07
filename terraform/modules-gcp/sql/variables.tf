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
# SQL Configuration
#------------------------------------------------------------------

variable "sql_config" {
  type = list(object({
    name             = string
    database_version = optional(string, "POSTGRES_16")
    tier             = optional(string, "db-custom-1-3840")
    database_name    = string
    username         = string
    password         = string
    private_network  = optional(string, null)
    labels           = optional(map(string), {})
  }))

  description = "Cloud SQL Postgres instances, databases and users"
  default     = []
}
