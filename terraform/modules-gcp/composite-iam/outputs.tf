output "project" {
  description = "Configured GCP project"
  value       = try(local.cfg.global.project, "")
}
