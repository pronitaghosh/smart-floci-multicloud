#------------------------------------------------------------------
# Module: IAM Role
#------------------------------------------------------------------

resource "aws_iam_role" "floci_iam_role" {
  for_each = local.roles

  name        = each.key
  description = each.value.description

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = each.value.trusted_service }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(
    var.global_config.tags,
    each.value.tags,
    { Name = each.key }
  )
}

resource "aws_iam_role_policy_attachment" "floci_iam_managed_policy" {
  for_each = local.managed_attachments

  role       = aws_iam_role.floci_iam_role[each.value.role_name].name
  policy_arn = each.value.policy_arn
}

resource "aws_iam_role_policy" "floci_iam_inline_policy" {
  for_each = local.inline_policies

  name = each.value.policy.name
  role = aws_iam_role.floci_iam_role[each.value.role_name].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for s in each.value.policy.statements : {
        Effect   = s.effect
        Action   = s.actions
        Resource = s.resources
      }
    ]
  })
}
