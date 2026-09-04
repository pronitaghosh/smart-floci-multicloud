#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------

locals {
  config       = yamldecode(var.config)
  global       = local.config.global
  resolved     = try(local.config.resolved, {})
  floci_compat = try(local.global.floci_compat, false)

  # --------------------------------------------------------------
  # EKS
  # --------------------------------------------------------------
  eks_config = [
    for c in try(local.config.clusters, []) : merge(c, {
      cluster_role_arn = try(local.resolved.role_arns[c.cluster_role_name], "")
      subnet_ids       = try(local.resolved.all_subnet_ids, [])
      node_groups = [
        for ng in try(c.node_groups, []) : merge(ng, {
          node_role_arn = try(local.resolved.role_arns[ng.node_role_name], "")
          subnet_ids    = try(local.resolved.all_subnet_ids, [])
        })
      ]
    })
  ]

  # --------------------------------------------------------------
  # ALB
  # --------------------------------------------------------------
  alb_config = [
    for lb in try(local.config.load_balancers, []) : merge(lb, {
      vpc_id             = try(local.resolved.vpc_id, "")
      subnet_ids         = try(local.resolved.public_subnet_ids, [])
      security_group_ids = compact([try(local.resolved.security_group_ids.alb, "")])
      listeners = [
        for l in try(lb.listeners, []) : merge(l, {
          certificate_arn = try(l.certificate_name, null) == null ? null : try(local.resolved.acm_certificate_arns[l.certificate_name], null)
        }) if try(l.create, true)
      ]
    })
  ]

  # --------------------------------------------------------------
  # CloudFront -- empty against floci; see docs/floci-gaps.md
  # --------------------------------------------------------------
  # floci's GetDistribution omits OriginGroups, and aws provider 6.61.0
  # dereferences it without a nil check (distribution.go:1150), segfaulting the
  # provider mid-apply and taking unrelated in-flight resources down with it.
  # There is no Terraform-side fix, so CloudFront is skipped entirely.
  cloudfront_config = local.floci_compat ? [] : [
    for d in try(local.config.cloudfront_distributions, []) : merge(d, {
      bucket_id                   = d.bucket_name
      bucket_regional_domain_name = try(local.resolved.bucket_regional_domain_names[d.bucket_name], "")
      acm_certificate_arn         = try(d.certificate_name, null) == null ? null : try(local.resolved.acm_certificate_arns[d.certificate_name], null)
    }) if try(d.create, true)
  ]

  # --------------------------------------------------------------
  # Vault (runtime half; the unseal key and secret containers live in stateful)
  # --------------------------------------------------------------
  # A pod's localhost is its own loopback, so in-cluster clients reach the
  # emulated AWS API at floci's address on the docker network.
  in_cluster_endpoint = try(local.global.in_cluster_endpoint_url, "http://172.18.0.2:4566")

  vault_config = [
    for v in try(local.config.vault, []) : merge(v, {
      unseal_key_id             = try(local.resolved.vault_unseal_key_ids[v.name], "")
      kms_endpoint              = local.in_cluster_endpoint
      aws_endpoint_url          = local.in_cluster_endpoint
      aws_region                = local.global.region
      root_token_secret_name    = try(local.resolved.vault_root_token_secrets[v.name], "")
      recovery_keys_secret_name = try(local.resolved.vault_recovery_key_secrets[v.name], "")
    })
  ]

  # --------------------------------------------------------------
  # ArgoCD
  # --------------------------------------------------------------
  argocd_config = [
    for a in try(local.config.argocd, []) : merge(a, {
      aws_endpoint_url = local.in_cluster_endpoint
    })
  ]

  # --------------------------------------------------------------
  # SSM parameters owned by this stack
  # --------------------------------------------------------------
  alb_dns = try(values(module.alb.dns_names)[0], "")
  cf_dns  = try(values(module.cloudfront.distribution_domain_names)[0], "")

  # Presence is decided from config (is an ALB configured?), never from the
  # output value -- an unknown value in the conditional would make the list
  # length unknown at plan time and break the downstream for_each.
  ssm_config = [
    {
      name   = "/${local.global.client_name}/gateway_url"
      value  = "http://${local.alb_dns}"
      create = length(local.alb_config) > 0
    },
    {
      name   = "/${local.global.client_name}/frontend_url"
      value  = "https://${local.cf_dns}"
      create = length(local.cloudfront_config) > 0
    },
  ]
}
