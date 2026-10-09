#------------------------------------------------------------------
# Module: Cloud Run service
#------------------------------------------------------------------
# Docker-backed data plane (Block 0 proven, nginx sidecar). deletion_protection
# is false for demo lifecycle. Image is nginx placeholder until Block 6 wires
# Artifact Registry addresses. nginx listens on 80 and ignores PORT, so the
# placeholder probes 80; the config port is the app contract, not the probe.
#------------------------------------------------------------------

resource "google_cloud_run_v2_service" "floci_run" {
  for_each = local.services

  name                = each.key
  location            = var.global_config.region
  deletion_protection = false
  ingress             = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = "nginx:latest"
      ports {
        container_port = 80
      }
    }
  }
}
