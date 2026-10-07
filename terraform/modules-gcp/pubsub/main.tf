#------------------------------------------------------------------
# Module: PubSub
#------------------------------------------------------------------

resource "google_pubsub_topic" "floci_topic" {
  for_each = local.topics

  name = each.key

  labels = merge(
    var.global_config.labels,
    each.value.labels,
  )
}

resource "google_pubsub_subscription" "floci_subscription" {
  for_each = local.subscriptions

  name  = each.key
  topic = google_pubsub_topic.floci_topic[each.value.topic_name].name

  labels = merge(
    var.global_config.labels,
    each.value.labels,
  )
}
