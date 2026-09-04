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
# ALB Configuration
#------------------------------------------------------------------

variable "alb_config" {
  type = list(object({
    name       = string
    internal   = optional(bool, false)
    vpc_id     = string
    subnet_ids = list(string)

    security_group_ids = optional(list(string), [])

    target_groups = optional(list(object({
      name        = string
      port        = optional(number, 80)
      protocol    = optional(string, "HTTP")
      target_type = optional(string, "ip")
      health_check = optional(object({
        path                = optional(string, "/healthz")
        healthy_threshold   = optional(number, 2)
        unhealthy_threshold = optional(number, 3)
        interval            = optional(number, 15)
        timeout             = optional(number, 5)
      }), {})
      tags = optional(map(string), {})
    })), [])

    listeners = optional(list(object({
      port                 = number
      protocol             = optional(string, "HTTP")
      default_target_group = string
      certificate_arn      = optional(string, null)
    })), [])

    tags = optional(map(string), {})
  }))

  description = "Application load balancers, target groups and listeners"
  default     = []
}
