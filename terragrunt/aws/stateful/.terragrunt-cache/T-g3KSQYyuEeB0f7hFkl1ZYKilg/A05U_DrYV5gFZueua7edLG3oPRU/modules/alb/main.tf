#------------------------------------------------------------------
# Module: ALB
#------------------------------------------------------------------

resource "aws_lb" "floci_lb" {
  for_each = local.load_balancers

  name               = each.key
  internal           = each.value.internal
  load_balancer_type = "application"
  security_groups    = each.value.security_group_ids
  subnets            = each.value.subnet_ids

  tags = merge(
    var.global_config.tags,
    each.value.tags,
    { Name = each.key }
  )
}

# target_type "ip" matches how the AWS Load Balancer Controller registers pods
# on real EKS. floci's ALB has no route to the k3s pod CIDR, so the demo
# registers the node's NodePort instead -- see scripts/register-alb-targets.sh.
resource "aws_lb_target_group" "floci_lb_target_group" {
  for_each = local.target_groups

  name        = each.key
  port        = each.value.port
  protocol    = each.value.protocol
  vpc_id      = each.value.vpc_id
  target_type = each.value.target_type

  health_check {
    path                = each.value.health_check.path
    healthy_threshold   = each.value.health_check.healthy_threshold
    unhealthy_threshold = each.value.health_check.unhealthy_threshold
    interval            = each.value.health_check.interval
    timeout             = each.value.health_check.timeout
  }

  tags = merge(
    var.global_config.tags,
    each.value.tags,
    { Name = each.key }
  )
}

resource "aws_lb_listener" "floci_lb_listener" {
  for_each = local.listeners

  load_balancer_arn = aws_lb.floci_lb[each.value.lb_name].arn
  port              = each.value.port
  protocol          = each.value.protocol
  certificate_arn   = each.value.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.floci_lb_target_group[each.value.default_target_group].arn
  }
}
