# demo-cicd — Gabriel De la Rivera

[![CI/CD](https://github.com/Gabrieldla/demo-cicd/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/Gabrieldla/demo-cicd/actions/workflows/ci-cd.yml)

> 📄 **[Cómo funciona el pipeline →](./PIPELINE.md)**: el diagrama, qué hace cada una de las ocho
> etapas, qué pasa si falla, las herramientas que cambié y cómo se tratan las vulnerabilidades.

---

## El enunciado original de la plantilla


Curso IF-1116, Tópicos de Tecnologías de Información, semestre 2026-II. Semana 06.

Aquí les dejo una aplicación completa y funcionando: el libro de visitas del LAB-02, ya contenerizado, con pruebas, con manifiestos de Kubernetes y con métricas. Lo que **no** tiene es el pipeline. Eso lo construyen ustedes siguiendo la [guía práctica de la Semana 06](https://github.com/urp-topicos-2026-2/.github-private/blob/main/semanas/S06/guia-pipeline.md), y lo extienden en el [LAB-04](https://github.com/urp-topicos-2026-2/.github-private/blob/main/semanas/S06/laboratorio/lab-04.md).

Todo lo que está aquí lo probé y funciona: lint, pruebas unitarias, pruebas de integración, Compose y los manifiestos. Si algo se pone en rojo en su pipeline, el problema está en el pipeline, y eso es justamente lo que tienen que resolver.

## Cómo usarlo

No hagan fork. Este repositorio es una **plantilla**: arriba a la derecha, **Use this template → Create a new repository**. Pónganle el nombre `demo-cicd`, en **su** cuenta y **público**. Público porque GitHub Actions y GitHub Packages son gratis sin límite para repositorios públicos, y porque el pipeline es la evidencia que yo reviso.

## Qué hay aquí

```
web/                    nginx: sirve la página y reenvía /api/ al backend
    Dockerfile          imagen sin root (nginx-unprivileged), escucha en 8080
    nginx.conf
    public/             index.html, estilos.css, libro-de-visitas.js
api/                    la API en Node.js (Express), con métricas para Prometheus en /metrics
    Dockerfile
    app.js              la aplicación, separada del arranque para poder probarla sin base de datos
    server.js           el arranque: pool de Postgres, puerto, señales
db/                     Postgres con las tablas ya incluidas
tests/
    unit/               pruebas unitarias de la API, con un pool falso (Vitest + Supertest)
    site/               pruebas del sitio estático (Vitest + jsdom)
    integration/        pruebas contra la aplicación completa, entrando por web (fetch)
scripts/
    smoke.sh            cinco comprobaciones rápidas contra un ambiente desplegado
    desplegar.sh        kubectl kustomize + reemplazo de imágenes + kubectl apply
k8s/
    base/               Deployments, Services, ConfigMap y PVC
    overlays/dev/       namespace demo-dev
    overlays/staging/   namespace demo-staging, web por NodePort 30090, dos réplicas de api
observabilidad/         Prometheus y Grafana con un dashboard RED ya armado
compose.yaml            la aplicación en su máquina, con perfil opcional de observabilidad
.devcontainer/          para que todo arranque solo en GitHub Codespaces
```

## Correrlo en su máquina

```bash
cp .env.example .env          # y cambien la contraseña
docker compose up -d --build --wait
open http://localhost:8080    # en Windows: start http://localhost:8080
```

Con observabilidad:

```bash
docker compose --profile observabilidad up -d --build --wait
open http://localhost:9090    # Prometheus
open http://localhost:3001    # Grafana, usuario admin, contraseña admin
```

## Las pruebas, una por una

```bash
npm ci && npm ci --prefix api   # una sola vez

npm run lint                    # ESLint sobre el JavaScript, HTMLHint sobre el HTML
npm run test:unit               # 9 pruebas, sin base de datos, en menos de un segundo
npm run test:site               # 6 pruebas sobre web/public
npm run test:integration        # 6 pruebas contra http://localhost:8080 (la app tiene que estar levantada)
APP_URL=http://localhost:30090 npm run test:integration   # las mismas, contra otro ambiente
bash scripts/smoke.sh http://localhost:8080
```

Los `Dockerfile` se revisan con [Hadolint](https://github.com/hadolint/hadolint):

```bash
docker run --rm -i hadolint/hadolint < api/Dockerfile
```

## La API

| Método y ruta | Qué hace | Respuesta |
|---|---|---|
| `GET /api/health` | Dice si el servicio está sano | `200` con `{"status":"ok"}`, o `503` si no puede hablar con la base de datos |
| `GET /api/mensajes` | Lista los mensajes, el más reciente primero | `200` con un arreglo JSON |
| `POST /api/mensajes` | Crea un mensaje. Recibe `{"nombre":"...","mensaje":"..."}` | `201` con el mensaje creado, o `400` si falta un campo o el mensaje pasa de 280 caracteres |
| `GET /metrics` | Métricas en formato Prometheus | Solo dentro de la red. nginx devuelve `404` si alguien la pide desde afuera |

Toda la configuración entra por variables de entorno: `PORT`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` y `DB_PASSWORD`. En el código no hay ninguna contraseña, y así debe seguir.

## Kubernetes

Los manifiestos usan imágenes `demo-cicd-web:local`, `demo-cicd-api:local` y `demo-cicd-db:local`. El script `scripts/desplegar.sh` las cambia por las de su registro antes de aplicar:

```bash
kubectl create namespace demo-staging
kubectl -n demo-staging create secret generic db-credenciales --from-literal=DB_PASSWORD="$(openssl rand -hex 16)"
scripts/desplegar.sh k8s/overlays/staging ghcr.io/<usuario>/demo-cicd sha-<commit>
kubectl -n demo-staging rollout status deploy/web deploy/api deploy/db
open http://localhost:30090
```

El Secret `db-credenciales` se crea **en el clúster**, una sola vez. No está en el repositorio ni lo crea el pipeline de staging. Los pods llevan `imagePullSecrets: ghcr`: si sus paquetes son públicos, ese Secret no hace falta y Kubernetes lo ignora; si son privados, créenlo con un token que tenga `read:packages`.

## Roturas a propósito (B3, y una más para el B2)

Cinco ramas rompen el pipeline una etapa cada vez, para comprobar que cada compuerta frena de verdad y para medir cuánto cuesta enterarse tarde. Las cuatro primeras son las que pide el B3; la quinta la agregué para probar la herramienta nueva del B2. Las ramas y sus PR quedan abiertas a propósito: son la evidencia, no cambios que quiera integrar.

| # | Rama / PR | Qué rompí | Etapa que lo detuvo | Tiempo hasta el fallo | Run |
|---|---|---|---|---|---|
| 1 | [`romper/1-lint`](../../pull/4) | `api/roto.js` declara una variable que nunca usa (`no-unused-vars`) | 1. Lint | **23 s** | [40248526621](../../actions/runs/40248526621) |
| 2 | [`romper/2-sast`](../../pull/5) | una ruta de Express que hace `eval(req.query.expresion)` | 2. SAST (Semgrep) | **20 s** | [40258084332](../../actions/runs/40258084332) |
| 3 | [`romper/3-pruebas`](../../pull/6) | `GET /api/estadisticas` devuelve el total como texto, no como número | 3. Pruebas unitarias | **31 s** | [40249321314](../../actions/runs/40249321314) |
| 4 | [`romper/4-seguridad`](../../pull/7) | `web/Dockerfile` vuelve a `nginx:1.25-alpine` y quita el `apk upgrade`: 45 HIGH con parche | 6. Escaneo de imagen | **147 s** | [40249853149](../../actions/runs/40249853149) |
| 5 | [`romper/5-secreto`](../../pull/16) | la contraseña de Postgres escrita en `api/server.js` | 2. Secretos (TruffleHog) | **23 s** | [40260425572](../../actions/runs/40260425572) |

Lo que importa es la última columna. El mismo tipo de descuido humano cuesta **23 segundos** si lo agarra el lint y **147 segundos** —seis veces más— si hay que construir y publicar tres imágenes antes de que Trivy pueda mirarlas. Por eso el pipeline va de lo barato a lo caro, y no al revés.

La rotura 5 es distinta a propósito: el código **funciona perfectamente**, no hay error de sintaxis ni prueba que falle. Lo único mal es que hay una credencial en el repositorio, y el pipeline lo frena igual.

Dos de estas roturas no se detuvieron donde debían, y ahí está lo que de verdad aprendí:

- La #3 pasó **en verde** la etapa de pruebas unitarias en el [primer intento](../../actions/runs/40248563301) y la agarró la etapa 4, 79 segundos después. La compuerta estaba desactivada sin que nadie lo supiera, por una tubería sin `pipefail`.
- La #2 pasó **el pipeline completo en verde** en el [primer intento](../../actions/runs/40248534371): tres minutos, doce jobs, todo limpio, con un `eval()` sobre entrada del usuario dentro.

Y probando la #5 descubrí que TruffleHog, con la configuración que le puse, calla ante cuatro de cada cinco secretos de prueba. Las tres cosas están contadas con detalle en [BITACORA.md](BITACORA.md).

## Lo que no está aquí, a propósito

- `.github/workflows/`: el pipeline. Es el trabajo de la guía y del laboratorio
- `.github/dependabot.yml`
- Los ambientes de GitHub (`dev`, `staging`) y la protección de `main`
- La configuración de los runners, de GitLab CI, de Argo CD y de todo lo que piden los retos

## Dudas

En el [issue de entrega del LAB-04](https://github.com/urp-topicos-2026-2/.github-private/issues). Cuando pregunten, pasen el enlace al run que falló, digan en qué job y en qué paso, qué esperaban y qué pasó.

Ing. Ronald Requena Crispín
