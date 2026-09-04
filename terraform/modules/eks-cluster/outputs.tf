#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "cluster_names" {
  value = { for k, c in aws_eks_cluster.floci_eks_cluster : k => c.name }
}

output "cluster_endpoints" {
  value = { for k, c in aws_eks_cluster.floci_eks_cluster : k => c.endpoint }
}

output "cluster_arns" {
  value = { for k, c in aws_eks_cluster.floci_eks_cluster : k => c.arn }
}
