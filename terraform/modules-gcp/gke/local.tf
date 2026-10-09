#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------

locals {
  clusters = {
    for c in var.gke_config : c.name => c
  }

  node_pools = merge([
    for c in var.gke_config : {
      for np in try(c.node_pools, []) : "${c.name}/${np.name}" => merge(np, {
        cluster_location = c.location
        cluster_name     = c.name
      })
    }
  ]...)
}
