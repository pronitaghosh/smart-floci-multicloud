#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "namespaces" {
  value = { for k, n in kubernetes_namespace.floci_argocd_namespace : k => n.metadata[0].name }
}

output "application_names" {
  value = { for k, a in local.installs : k => var.global_config.client_name }
}

output "port_forward_hint" {
  value = {
    for k, a in local.installs :
    k => "kubectl port-forward -n ${a.namespace} svc/${k}-argocd-server 8080:80"
  }
}
