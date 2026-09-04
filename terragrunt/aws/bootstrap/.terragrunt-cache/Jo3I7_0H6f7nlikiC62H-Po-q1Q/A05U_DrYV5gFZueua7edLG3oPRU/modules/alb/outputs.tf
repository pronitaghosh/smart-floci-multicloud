#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "dns_names" {
  value = { for k, lb in aws_lb.floci_lb : k => lb.dns_name }
}

output "target_group_arns" {
  value = { for k, tg in aws_lb_target_group.floci_lb_target_group : k => tg.arn }
}
