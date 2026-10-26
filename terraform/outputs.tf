output "checks_obligatorios" {
  description = "Para comprobar de un vistazo que la lista coincide con los jobs del workflow."
  value       = var.checks_obligatorios
}

output "ambientes" {
  value = {
    dev     = github_repository_environment.dev.environment
    staging = github_repository_environment.staging.environment
  }
}
