#------------------------------------------------------------------
# Module: Networking
#------------------------------------------------------------------

resource "aws_vpc" "floci_vpc" {
  cidr_block           = var.network_config.cidr
  enable_dns_support   = var.network_config.enable_dns_support
  enable_dns_hostnames = var.network_config.enable_dns_hostnames

  tags = merge(
    var.global_config.tags,
    var.network_config.tags,
    { Name = "${local.name}-vpc" }
  )
}

resource "aws_internet_gateway" "floci_internet_gw" {
  vpc_id = aws_vpc.floci_vpc.id

  tags = merge(
    var.global_config.tags,
    var.network_config.tags,
    { Name = "${local.name}-igw" }
  )
}

#------------------------------------------------------------------
# Subnets
#------------------------------------------------------------------

resource "aws_subnet" "floci_subnet" {
  for_each = local.subnets

  vpc_id                  = aws_vpc.floci_vpc.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = each.value.type == "public"

  tags = merge(
    var.global_config.tags,
    local.subnet_role_tags[each.value.type],
    each.value.tags,
    { Name = each.key }
  )
}

#------------------------------------------------------------------
# Routing
#------------------------------------------------------------------

resource "aws_route_table" "floci_public_rt" {
  vpc_id = aws_vpc.floci_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.floci_internet_gw.id
  }

  tags = merge(
    var.global_config.tags,
    { Name = "${local.name}-public-rt" }
  )
}

resource "aws_route_table" "floci_private_rt" {
  vpc_id = aws_vpc.floci_vpc.id

  tags = merge(
    var.global_config.tags,
    { Name = "${local.name}-private-rt" }
  )
}

resource "aws_route_table_association" "floci_public_rta" {
  for_each = local.public_subnets

  subnet_id      = aws_subnet.floci_subnet[each.key].id
  route_table_id = aws_route_table.floci_public_rt.id
}

resource "aws_route_table_association" "floci_private_rta" {
  for_each = local.private_subnets

  subnet_id      = aws_subnet.floci_subnet[each.key].id
  route_table_id = aws_route_table.floci_private_rt.id
}

#------------------------------------------------------------------
# Security Groups
#------------------------------------------------------------------

resource "aws_security_group" "floci_sg" {
  for_each = local.security_groups

  name        = "${local.name}-${each.key}-sg"
  description = each.value.description
  vpc_id      = aws_vpc.floci_vpc.id

  dynamic "ingress" {
    for_each = each.value.ingress
    content {
      description = ingress.value.description
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.global_config.tags,
    each.value.tags,
    { Name = "${local.name}-${each.key}-sg" }
  )
}
