#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "topic_ids" {
  value = { for k, t in google_pubsub_topic.floci_topic : k => t.id }
}

output "subscription_ids" {
  value = { for k, s in google_pubsub_subscription.floci_subscription : k => s.id }
}
