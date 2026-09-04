#------------------------------------------------------------------
# Module: EKS Cluster
#------------------------------------------------------------------

resource "aws_eks_cluster" "floci_eks_cluster" {
  for_each = local.clusters

  name     = each.key
  role_arn = each.value.cluster_role_arn
  version  = each.value.kubernetes_version

  vpc_config {
    subnet_ids = each.value.subnet_ids
  }

  tags = merge(
    var.global_config.tags,
    each.value.tags,
    { Name = each.key }
  )
}

resource "aws_eks_node_group" "floci_eks_node_group" {
  for_each = local.node_groups

  cluster_name    = aws_eks_cluster.floci_eks_cluster[each.value.cluster_name].name
  node_group_name = each.value.node_group.name
  node_role_arn   = each.value.node_group.node_role_arn
  subnet_ids      = each.value.subnet_ids
  instance_types  = each.value.node_group.instance_types

  scaling_config {
    desired_size = each.value.node_group.desired_size
    min_size     = each.value.node_group.min_size
    max_size     = each.value.node_group.max_size
  }

  tags = merge(
    var.global_config.tags,
    each.value.node_group.tags,
    { Name = each.value.node_group.name }
  )
}
