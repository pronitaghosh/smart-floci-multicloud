#------------------------------------------------------------------
# Module: ECR Repository
#------------------------------------------------------------------

resource "aws_ecr_repository" "floci_ecr_repository" {
  for_each = local.repositories

  name                 = "${var.global_config.client_name}/${each.key}"
  image_tag_mutability = each.value.image_tag_mutability
  force_delete         = each.value.force_delete

  image_scanning_configuration {
    scan_on_push = each.value.scan_on_push
  }

  tags = merge(
    var.global_config.tags,
    each.value.tags,
    { Name = "${var.global_config.client_name}/${each.key}" }
  )
}
