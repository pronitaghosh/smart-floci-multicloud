#------------------------------------------------------------------
# Outputs
#------------------------------------------------------------------

output "network_id" {
  value = google_compute_network.floci_network.id
}

# Keyed by subnet name so consumers select by intent, not by list index.
output "subnet_ids" {
  value = { for k, s in google_compute_subnetwork.floci_subnet : k => s.id }
}

output "subnet_cidrs" {
  value = { for k, s in google_compute_subnetwork.floci_subnet : k => s.ip_cidr_range }
}

output "firewall_ids" {
  value = { for k, f in google_compute_firewall.floci_firewall : k => f.id }
}
