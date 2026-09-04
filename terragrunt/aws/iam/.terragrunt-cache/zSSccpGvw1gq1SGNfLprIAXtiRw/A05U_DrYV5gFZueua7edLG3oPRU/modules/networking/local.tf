#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------

locals {
  name = var.network_config.name

  # Keyed maps drive every for_each below. Keys are stable, human-readable and
  # derived from config -- never from list position.
  subnets = {
    for s in var.network_config.subnets : "${local.name}-${s.name}" => s
  }

  public_subnets  = { for k, s in local.subnets : k => s if s.type == "public" }
  private_subnets = { for k, s in local.subnets : k => s if s.type == "private" }

  security_groups = {
    for sg in var.network_config.security_groups : sg.name => sg
  }

  # EKS discovers subnets by these tags; they must be present for the ALB and
  # internal-ELB roles to resolve.
  cluster_tag = { "kubernetes.io/cluster/${var.global_config.client_name}" = "shared" }

  subnet_role_tags = {
    public  = merge(local.cluster_tag, { "kubernetes.io/role/elb" = "1" })
    private = merge(local.cluster_tag, { "kubernetes.io/role/internal-elb" = "1" })
  }
}
