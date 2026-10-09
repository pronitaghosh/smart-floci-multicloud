#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "project" {
  description = "Configured GCP project"
  value       = try(local.global.project, "")
}

output "cluster_names" {
  value = module.gke.cluster_names
}

output "cluster_endpoints" {
  value = module.gke.cluster_endpoints
}

output "node_pool_names" {
  value = module.gke.node_pool_names
}

output "run_service_names" {
  value = module.run.service_names
}

output "run_service_uris" {
  value = module.run.service_uris
}

output "argocd_namespaces" {
  value = module.argocd.namespaces
}

output "argocd_port_forward" {
  value = module.argocd.port_forward_hint
}
