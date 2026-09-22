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
# ArgoCD Configuration
#------------------------------------------------------------------

variable "argocd_config" {
  type = list(object({
    name               = string
    namespace          = optional(string, "argocd")
    chart_version      = optional(string, "7.7.11")
    apps_chart_version = optional(string, "2.0.2")

    # The GitOps source. Argo owns everything under this path; anything still
    # applied imperatively inside it will be reverted on the next sync.
    repo_url        = string
    target_revision = optional(string, "main")
    path            = optional(string, "k8s")

    destination_namespace = optional(string, "smartcloud")

    auto_sync = optional(bool, true)
    self_heal = optional(bool, true)
    prune     = optional(bool, false)

    # Written to Secrets Manager so the admin password is retrievable the same
    # way Vault's root token is.
    admin_password_secret_name = optional(string, "")
    aws_endpoint_url           = optional(string, "http://172.18.0.2:4566")

    tags = optional(map(string), {})
  }))

  description = "ArgoCD installations and the Application each one manages"
  default     = []
}
