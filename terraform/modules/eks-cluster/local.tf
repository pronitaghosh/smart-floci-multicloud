#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------

locals {
  clusters = { for c in var.eks_config : c.name => c }

  node_groups = merge([
    for cname, c in local.clusters : {
      for ng in c.node_groups : "${cname}/${ng.name}" => {
        cluster_name = cname
        node_group   = ng
        subnet_ids   = coalesce(ng.subnet_ids, c.subnet_ids)
      }
    }
  ]...)
}
