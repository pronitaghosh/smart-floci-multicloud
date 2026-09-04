#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "vpc_id" {
  value = aws_vpc.floci_vpc.id
}

output "vpc_cidr" {
  value = aws_vpc.floci_vpc.cidr_block
}

# Keyed by subnet name so consumers select by intent, not by list index.
output "subnet_ids" {
  value = { for k, s in aws_subnet.floci_subnet : k => s.id }
}

output "public_subnet_ids" {
  value = [for k, s in aws_subnet.floci_subnet : s.id if local.subnets[k].type == "public"]
}

output "private_subnet_ids" {
  value = [for k, s in aws_subnet.floci_subnet : s.id if local.subnets[k].type == "private"]
}

output "all_subnet_ids" {
  value = [for s in aws_subnet.floci_subnet : s.id]
}

output "security_group_ids" {
  value = { for k, sg in aws_security_group.floci_sg : k => sg.id }
}
