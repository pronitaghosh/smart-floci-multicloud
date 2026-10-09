#------------------------------------------------------------------
# Module: GKE
#------------------------------------------------------------------
# Real k3s sidecar via the container API (Block 0 proven). Requires
# container_custom_endpoint in host mode. Node pool autoscaling not
# asserted locally; count is metadata-only like AWS EKS scaling config.
#------------------------------------------------------------------

resource "google_container_cluster" "floci_gke" {
  for_each = local.clusters

  name     = each.key
  location = each.value.location

  initial_node_count       = 1
  remove_default_node_pool = true
  deletion_protection      = false
}

resource "google_container_node_pool" "floci_pool" {
  for_each = local.node_pools

  name     = each.value.name
  location = each.value.cluster_location
  cluster  = google_container_cluster.floci_gke[each.value.cluster_name].name
  node_count = each.value.node_count

  node_config {
    machine_type = each.value.machine_type
  }

  ignore_node_count_changes = true
}
