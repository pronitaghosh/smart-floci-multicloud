#------------------------------------------------------------------
# Module: GCP Network
#------------------------------------------------------------------
# Firewall rules are shape-only locally: no real packet enforcement in the
# emulator. source_ranges is required by the API even for shape-only rules.
#------------------------------------------------------------------

resource "google_compute_network" "floci_network" {
  name                    = local.name
  auto_create_subnetworks = var.network_config.auto_create_subnetworks
}

resource "google_compute_subnetwork" "floci_subnet" {
  for_each = local.subnets

  name          = each.key
  ip_cidr_range = each.value.cidr
  region        = each.value.region
  network       = google_compute_network.floci_network.id
}

resource "google_compute_firewall" "floci_firewall" {
  for_each = local.firewall_rules

  name    = "${local.name}-${each.key}"
  network = google_compute_network.floci_network.id

  description   = each.value.description
  source_ranges = each.value.source_ranges

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  allow {
    protocol = "icmp"
  }
}
