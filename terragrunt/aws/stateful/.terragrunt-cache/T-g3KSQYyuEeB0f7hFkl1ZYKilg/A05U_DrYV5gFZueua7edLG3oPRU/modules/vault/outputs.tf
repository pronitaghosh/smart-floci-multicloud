#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "namespaces" {
  value = { for k, n in kubernetes_namespace.floci_vault_namespace : k => n.metadata[0].name }
}

output "release_names" {
  value = { for k, r in helm_release.floci_vault : k => r.name }
}

# Vault is reachable only inside the cluster: k3s publishes 6443 and nothing
# else, so a NodePort would not reach the host.
output "port_forward_hint" {
  value = {
    for k, v in local.clusters :
    k => "kubectl port-forward -n ${v.namespace} svc/${k} 8200:8200"
  }
}
