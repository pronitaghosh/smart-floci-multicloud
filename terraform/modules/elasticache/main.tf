#------------------------------------------------------------------
# Module: ElastiCache
#------------------------------------------------------------------

resource "aws_elasticache_subnet_group" "floci_cache_subnet_group" {
  for_each = local.subnet_groups

  name       = "${var.global_config.client_name}-${each.key}-subnets"
  subnet_ids = each.value.subnet_ids
}

resource "aws_elasticache_replication_group" "floci_cache_replication_group" {
  for_each = local.clusters

  replication_group_id = "${var.global_config.client_name}-${each.key}"
  description          = each.value.description
  engine               = each.value.engine
  node_type            = each.value.node_type
  num_cache_clusters   = each.value.num_cache_clusters
  port                 = each.value.port

  subnet_group_name  = try(aws_elasticache_subnet_group.floci_cache_subnet_group[each.key].name, null)
  security_group_ids = each.value.security_group_ids

  tags = merge(
    var.global_config.tags,
    each.value.tags,
    { Name = "${var.global_config.client_name}-${each.key}" }
  )

  # floci reports both of these back differently from what it was asked for:
  #   port               - the requested value is ignored; floci allocates its
  #                        own (6379 -> 6380 when 6379 is taken), and because
  #                        port is Optional-not-Computed the drift forces a
  #                        replacement on every single plan.
  #   num_cache_clusters - always reported as 0, and IncreaseReplicaCount is
  #                        unsupported, so reconciling it fails the apply.
  #
  # Cost on real AWS: changing the port or scaling the cluster count through
  # Terraform requires removing this block first. That is a deliberate trade to
  # keep `terraform apply` idempotent against floci -- without it, re-running
  # the demo errors out every time. lifecycle cannot be variable-driven, so it
  # is unconditional rather than gated on a floci_compat flag.
  lifecycle {
    ignore_changes = [port, num_cache_clusters]
  }
}
