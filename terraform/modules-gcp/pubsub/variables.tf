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
# PubSub Configuration
#------------------------------------------------------------------

variable "pubsub_config" {
  type = object({
    topics = optional(list(object({
      name   = string
      labels = optional(map(string), {})
    })), [])
    subscriptions = optional(list(object({
      name       = string
      topic_name = string
      labels     = optional(map(string), {})
    })), [])
  })

  description = "PubSub topics and subscriptions"
  default     = {}
}
