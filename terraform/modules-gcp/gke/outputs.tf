#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "cluster_names" {
  value = { for k, c in google_container_cluster.floci_gke : k => c.name }
}

output "cluster_endpoints" {
  value = { for k, c in google_container_cluster.floci_gke : k => c.endpoint }
}

output "node_pool_names" {
  value = { for k, p in google_container_node_pool.floci_pool : k => p.name }
}
