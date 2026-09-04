#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "eks_cluster_names" {
  value = module.eks_cluster.cluster_names
}

output "eks_cluster_name" {
  value = try(values(module.eks_cluster.cluster_names)[0], null)
}

output "eks_cluster_endpoint" {
  value = try(values(module.eks_cluster.cluster_endpoints)[0], null)
}

output "alb_dns_name" {
  value = try(values(module.alb.dns_names)[0], null)
}

output "target_group_arns" {
  value = module.alb.target_group_arns
}

output "cloudfront_domain_name" {
  value = try(values(module.cloudfront.distribution_domain_names)[0], null)
}

#------------------------------------------------------------------
# Platform
#------------------------------------------------------------------

output "vault_namespaces" {
  value = module.vault.namespaces
}

output "vault_port_forward" {
  value = module.vault.port_forward_hint
}

output "argocd_namespaces" {
  value = module.argocd.namespaces
}

output "argocd_port_forward" {
  value = module.argocd.port_forward_hint
}
