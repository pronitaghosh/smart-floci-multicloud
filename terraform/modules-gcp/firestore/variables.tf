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
# Firestore Configuration
#------------------------------------------------------------------

variable "firestore_config" {
  type = list(object({
    name        = string
    location_id = optional(string, "us-central1")
    type        = optional(string, "FIRESTORE_NATIVE")
  }))

  description = "Firestore databases, provisioned via SDK"
  default     = []
}
