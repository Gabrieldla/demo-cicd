# La protección de main y los dos ambientes, como código.
#
# Los configuré a mano en la interfaz mientras armaba el pipeline, y eso tiene dos
# problemas que no se ven hasta que duelen: no queda constancia de POR QUÉ está así,
# y si el repositorio se recrea (o se hace otro para el trabajo final) hay que
# acordarse de todo clic. Esto lo deja escrito y revisable en un PR.

# ─── La compuerta técnica ────────────────────────────────────────────────────────
resource "github_repository_ruleset" "main" {
  name        = "Proteger main"
  repository  = var.repositorio
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      # ~DEFAULT_BRANCH y no "refs/heads/main": si algún día la rama por defecto
      # cambia de nombre, la protección se va con ella en vez de quedarse
      # protegiendo una rama que ya no existe.
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    # Nada entra a main por push directo: todo pasa por un PR.
    pull_request {
      # Cero aprobaciones: trabajo solo. La compuerta aquí no es una persona
      # revisando, son los diez checks de abajo. En un equipo esto sería 1 o 2.
      required_approving_review_count   = 0
      dismiss_stale_reviews_on_push     = false
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_review_thread_resolution = false
    }

    required_status_checks {
      # false a propósito: no exijo que la rama esté al día con main antes de
      # mezclar. Con "true" cada merge invalida los checks de los demás PR
      # abiertos y hay que volver a correr el pipeline entero de cada uno.
      # Con un repositorio de una persona es solo tiempo perdido.
      strict_required_status_checks_policy = false

      dynamic "required_check" {
        for_each = var.checks_obligatorios
        content {
          context = required_check.value
        }
      }
    }
  }
}

# ─── Los ambientes ───────────────────────────────────────────────────────────────

# DEV no tiene protección y es correcto: nace y muere dentro del runner en cada
# push a main. No hay nada que proteger, y pedir aprobación para un ambiente que
# dura noventa segundos solo entrena a la gente a aprobar sin mirar.
resource "github_repository_environment" "dev" {
  repository  = var.repositorio
  environment = "dev"
}

# STAGING sí: es persistente, corre en mi máquina y tiene los datos del libro de
# visitas. Aquí está la compuerta humana del pipeline.
resource "github_repository_environment" "staging" {
  repository  = var.repositorio
  environment = "staging"

  # can_admins_bypass queda en true, que es el valor por defecto. Lo dejo así
  # a conciencia: soy el único administrador y el único revisor, así que
  # ponerlo en false no agrega seguridad, agrega la ilusión de que la agrega.
  can_admins_bypass = true

  reviewers {
    users = var.revisores_staging
  }

  deployment_branch_policy {
    # Solo ramas protegidas pueden desplegar a STAGING. Es decir: main. Sin esto,
    # cualquiera que empuje una rama podría pedir un despliegue al ambiente
    # persistente y saltarse los checks por el lado.
    protected_branches     = true
    custom_branch_policies = false
  }
}
