#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------

locals {
  # The filter must depend only on config. Testing p.value would make the map
  # KEYS depend on a resource attribute -- ECR repository URLs are not known
  # until apply -- and Terraform then refuses the for_each entirely:
  #   "for_each map includes keys derived from resource attributes that cannot
  #    be determined until apply".
  # Callers set create=false for a parameter whose source module is disabled.
  parameters = { for p in var.ssm_config : p.name => p if try(p.create, true) }
}
