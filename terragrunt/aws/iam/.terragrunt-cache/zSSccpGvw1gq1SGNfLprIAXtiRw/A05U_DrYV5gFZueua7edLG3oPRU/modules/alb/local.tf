#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------

locals {
  load_balancers = { for lb in var.alb_config : lb.name => lb }

  target_groups = merge([
    for lbname, lb in local.load_balancers : {
      for tg in lb.target_groups : tg.name => merge(tg, { lb_name = lbname, vpc_id = lb.vpc_id })
    }
  ]...)

  listeners = merge([
    for lbname, lb in local.load_balancers : {
      for l in lb.listeners : "${lbname}/${l.port}" => merge(l, { lb_name = lbname })
    }
  ]...)
}
