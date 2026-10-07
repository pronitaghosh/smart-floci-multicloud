#------------------------------------------------------------------
# Locals
#------------------------------------------------------------------

locals {
  topics = {
    for t in var.pubsub_config.topics : t.name => t
  }

  subscriptions = {
    for s in var.pubsub_config.subscriptions : s.name => s
  }
}
