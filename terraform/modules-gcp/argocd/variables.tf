#------------------------------------------------------------------
# Global Configuration
#------------------------------------------------------------------

variable "global_config" {
  type = object({
    client_name = string
    environment = string
    project     = string
    region      = string
    labels      = optional(map(string), {})
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

    # Written to Secret Manager so the admin password is retrievable the same
    # way the AWS port exposes it, via the emulator REST API.
    admin_password_secret_name = optional(string, "")
    gcp_endpoint_url           = optional(string, "http://localhost:4588")
    gcp_project                = optional(string, "floci-local")

    tags = optional(map(string), {})
  }))

  description = "ArgoCD installations and the Application each one manages"
  default     = []
}
