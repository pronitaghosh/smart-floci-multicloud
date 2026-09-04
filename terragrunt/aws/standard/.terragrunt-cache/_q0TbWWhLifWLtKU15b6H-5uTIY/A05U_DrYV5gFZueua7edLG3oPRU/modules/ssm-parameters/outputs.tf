#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "parameter_names" {
  value = [for p in aws_ssm_parameter.floci_ssm_parameter : p.name]
}

output "parameter_prefix" {
  value = "/${var.global_config.client_name}/"
}
