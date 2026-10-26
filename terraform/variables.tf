variable "propietario" {
  description = "La cuenta de GitHub dueña del repositorio."
  type        = string
  default     = "Gabrieldla"
}

variable "repositorio" {
  description = "El nombre del repositorio que se configura."
  type        = string
  default     = "demo-cicd"
}

variable "revisores_staging" {
  description = "Quién puede aprobar un despliegue a STAGING. Son ids numéricos de GitHub, no nombres: un nombre se puede cambiar, el id no."
  type        = list(number)
  default     = [179658806] # Gabrieldla
}

variable "checks_obligatorios" {
  description = <<-TEXTO
    Los checks que tienen que estar en verde para poder mezclar a main. Son los
    nombres de los jobs del workflow, literales: si se renombra un job allí y no
    aquí, el check deja de existir y la compuerta se queda esperando para siempre
    a algo que no va a llegar. Es el mismo error que cometí con el check de
    Dependabot, y tenerlos en un solo archivo es parte de no repetirlo.
  TEXTO
  type        = list(string)
  default = [
    "1. Lint (ESLint, HTMLHint, Hadolint)",
    "2. SAST (Semgrep) y secretos (TruffleHog)",
    "3. Pruebas unitarias y del sitio",
    "4. Pruebas de integración (Compose)",
    "5. Empaquetar y publicar (web)",
    "5. Empaquetar y publicar (api)",
    "5. Empaquetar y publicar (db)",
    "6. Escaneo de imagen (web)",
    "6. Escaneo de imagen (api)",
    "6. Escaneo de imagen (db)",
  ]
}
