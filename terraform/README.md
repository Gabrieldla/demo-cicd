# La plataforma también es código (Reto 6)

La protección de `main` y los ambientes `dev` y `staging` los configuré a mano en la interfaz de GitHub mientras armaba el pipeline. Esto los pone en Terraform.

## Por qué, si ya funcionaban

Porque un clic no deja constancia de **por qué** está así. El dato más caro de este directorio no es la lista de checks: son los comentarios al lado de cada decisión. `strict_required_status_checks_policy = false` no se explica solo, y dentro de tres meses yo tampoco me iba a acordar.

Y porque la lista de checks obligatorios y los nombres de los jobs del workflow **tienen que coincidir carácter por carácter**. Tenerlos en dos sitios distintos, uno en YAML y otro en una pantalla de configuración, es una trampa esperando: si renombro un job, el check deja de existir y la compuerta se queda esperando para siempre algo que no va a llegar. Ya me pasó con el check de Dependabot.

## Cómo correrlo

No tengo Terraform instalado en la máquina, y no lo necesito: va en contenedor con versión fija, igual que Semgrep, Trivy y ZAP en el pipeline.

```bash
export GITHUB_TOKEN="$(gh auth token)"   # no se escribe en ningún archivo

TF() {
  docker run --rm -v "$PWD:/tf" -w /tf -e GITHUB_TOKEN \
    hashicorp/terraform:1.17.0 "$@"
}

TF init
TF plan
```

El estado está en local y **no se versiona** (`.gitignore`): guarda en claro todo lo que Terraform administra, y este repositorio es público. Para una persona alcanza; en un equipo iría en un backend remoto con bloqueo, porque dos `apply` simultáneos sobre el mismo estado local lo corrompen.

El `.terraform.lock.hcl` **sí** se versiona, por lo mismo que las acciones van por SHA: fija el provider por hash.

## La configuración ya existía: se importó, no se recreó

Esto es lo que más me importaba hacer bien. Lo fácil —y lo destructivo— habría sido correr `terraform apply` sobre un estado vacío: Terraform habría intentado **crear** un ruleset que ya existe y dos ambientes que ya existen, y en el mejor caso falla, en el peor deja la rama sin protección a mitad de camino.

Lo correcto es traer lo que hay al estado y comprobar que el código lo describe:

```bash
TF import github_repository_ruleset.main        demo-cicd:25842994
TF import github_repository_environment.dev     demo-cicd:dev
TF import github_repository_environment.staging demo-cicd:staging
```

Y entonces el plan tiene que salir vacío:

```
github_repository_environment.dev: Refreshing state... [id=demo-cicd:dev]
github_repository_environment.staging: Refreshing state... [id=demo-cicd:staging]
github_repository_ruleset.main: Refreshing state... [id=25842994]

No changes. Your infrastructure matches the configuration.
```

Cero cambios significa que el código de este directorio **describe de verdad** lo que tiene el repositorio, no lo que yo creía que tenía. Si mañana alguien toca la protección de `main` desde la interfaz, `terraform plan` lo delata.

## Lo que no está aquí

El runner self-hosted. El enunciado deja elegir entre Terraform para la plataforma o Ansible para el runner, y elegí Terraform porque la protección de `main` es lo que de verdad no quiero perder: el runner se vuelve a instalar en veinte minutos, pero un repositorio sin compuertas se nota cuando ya entró algo.

Tampoco está el `GITHUB_TOKEN`, y nunca va a estar.
