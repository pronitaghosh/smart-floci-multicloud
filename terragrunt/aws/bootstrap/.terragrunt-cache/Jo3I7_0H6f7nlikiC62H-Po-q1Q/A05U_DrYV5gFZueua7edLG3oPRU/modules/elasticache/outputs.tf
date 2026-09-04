#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

# Real AWS populates primary_endpoint_address for a non-clustered group and
# leaves configuration_endpoint_address null; floci does the exact opposite.
# Taking whichever is set keeps one output correct on both.
output "primary_endpoints" {
  value = {
    for k, c in aws_elasticache_replication_group.floci_cache_replication_group :
    k => try(coalesce(c.primary_endpoint_address, c.configuration_endpoint_address), null)
  }
}

output "ports" {
  value = { for k, c in aws_elasticache_replication_group.floci_cache_replication_group : k => c.port }
}
