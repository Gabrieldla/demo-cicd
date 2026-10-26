# Versiones fijas, por lo mismo que las acciones van por SHA: si el provider cambia
# de comportamiento entre dos "terraform apply", el estado del repositorio cambia sin
# que nadie haya tocado este código.
terraform {
  required_version = "~> 1.17"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.6"
    }
  }
}

# El token NO va aquí. Se pasa por la variable de entorno GITHUB_TOKEN, para que no
# termine ni en el repositorio ni en el estado de Terraform.
provider "github" {
  owner = var.propietario
}
