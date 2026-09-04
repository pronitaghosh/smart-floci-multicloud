#------------------------------------------------------------------
# Module: RDS
#------------------------------------------------------------------

resource "aws_db_subnet_group" "floci_db_subnet_group" {
  for_each = local.instances

  name       = coalesce(each.value.subnet_group_name, "${var.global_config.client_name}-db-subnets")
  subnet_ids = each.value.subnet_ids

  tags = merge(
    var.global_config.tags,
    each.value.tags,
    { Name = coalesce(each.value.subnet_group_name, "${var.global_config.client_name}-db-subnets") }
  )
}

resource "aws_db_instance" "floci_db_instance" {
  for_each = local.instances

  identifier        = "${var.global_config.client_name}-${each.key}"
  engine            = each.value.engine
  engine_version    = each.value.engine_version
  instance_class    = each.value.instance_class
  allocated_storage = each.value.allocated_storage
  db_name           = each.value.db_name
  username          = each.value.username
  password          = each.value.password

  db_subnet_group_name   = aws_db_subnet_group.floci_db_subnet_group[each.key].name
  vpc_security_group_ids = each.value.vpc_security_group_ids

  skip_final_snapshot = each.value.skip_final_snapshot
  publicly_accessible = each.value.publicly_accessible

  storage_encrypted = each.value.storage_encrypted
  kms_key_id        = each.value.kms_key_arn

  tags = merge(
    var.global_config.tags,
    each.value.tags,
    { Name = "${var.global_config.client_name}-${each.key}" }
  )
}
