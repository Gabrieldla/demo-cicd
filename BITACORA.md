# Bitácora de decisiones (LAB-04)

Una entrada por reto intentado, y una por cada hallazgo que me obligó a cambiar algo.

---

## B2: las dos herramientas que cambié

### Gitleaks → TruffleHog

- **Decisión:** reemplacé Gitleaks por TruffleHog 3.99.7 en la etapa de secretos.
- **Alternativas que evalué:**
  - *Quedarme con Gitleaks*: es más rápido y su configuración por TOML es más sencilla de ajustar. Pero solo detecta **patrones**: si una cadena se parece a una llave de AWS, la marca, viva o muerta.
  - *detect-secrets de Yelp*: trabaja con una "línea base" de secretos conocidos que se versiona. Es cómodo en repositorios con muchos falsos positivos históricos, pero obliga a mantener ese archivo y a revisarlo en cada PR. Para un repositorio nuevo es más ceremonia que valor.
- **Por qué elegí esta:** TruffleHog, además de detectar el patrón, **verifica contra el servicio emisor si la credencial sigue viva**. Eso separa un secreto explotable de una cadena que solo lo parece, y es la diferencia entre una alerta que se atiende y una que se ignora. Un escáner que grita mucho acaba desactivado.
- **Cómo lo verifiqué:** lo corrí en local antes de subirlo (0 secretos, código de salida 0) y después en el pipeline. Con `--fail`, un hallazgo pone la etapa en rojo igual que antes.
- **Qué aprendí:** `--results=verified,unknown` es el ajuste que importa. Si se deja solo `verified`, TruffleHog calla ante credenciales de servicios que no sabe verificar, y eso es peor que un falso positivo.

### kind → k3d

- **Decisión:** el ambiente DEV efímero se crea con k3d v5.9.0 en vez de kind.
- **Alternativas que evalué:**
  - *kind*, que es lo que trae la guía: es el estándar de facto para Kubernetes en CI y levanta Kubernetes "vanilla".
  - *minikube*: más pesado y pensado para escritorio, no para un runner.
- **Por qué elegí esta:** k3d levanta **k3s**, que es exactamente la distribución que corre mi Rancher Desktop en STAGING. Con kind, DEV y STAGING eran dos Kubernetes distintos y lo que pasaba en uno no predecía lo que pasaba en el otro. Con k3d, el ambiente efímero se parece al persistente.
- **Qué no me funcionó:** la acción `AbsaOSS/k3d-action@v2.4.0` falla con `curl: (22) 404` y `Failed to install k3d`: intenta descargar una versión que ya no está publicada. Dejó `main` en rojo. Lo resolví instalando el binario directamente desde su release, con la versión fija, **sin `curl | bash`**: ejecutar un script remoto es el patrón exacto del ataque a la cadena de suministro que estudié en el LAB-03, y no tiene sentido protegerse de él en las acciones y abrirle la puerta aquí.

---

## B3: lo que encontré al romper el pipeline

La tabla con los enlaces está en el README. Aquí va lo que aprendí, que es más interesante que la tabla.

### Hallazgo 1: una tubería había desactivado una compuerta sin avisar

- **Qué pasó:** rompí a propósito el endpoint de estadísticas para que fallara la etapa 3 (pruebas unitarias). La etapa 3 pasó **en verde**. El fallo lo detectó la etapa 4, un minuto más tarde.
- **La causa:** el paso era `npm run test:unit 2>&1 | tee unit.txt`. Metí esa tubería para armar el resumen del run (B5). El shell por defecto de GitHub Actions es `bash -e`, **sin `pipefail`**: en una tubería solo cuenta el código de salida del último comando, que es `tee` y siempre devuelve 0.
- **Lo grave:** la compuerta de pruebas unitarias llevaba **varios runs sin poder frenar nada**, y el pipeline se veía verde todo el tiempo. Un pipeline que no puede fallar no está probando nada.
- **Cómo lo arreglé:** `defaults.run.shell: bash` a nivel de workflow, que hace que Actions use `bash --noprofile --norc -eo pipefail`.
- **Qué me llevo:** una mejora cosmética (un resumen bonito) desactivó un control de calidad. Y solo se notó porque rompí algo a propósito. Si no hubiera hecho el B3, habría entregado un pipeline que miente.

### Hallazgo 2: el SAST tenía un hueco

- **Qué pasó:** metí un `eval()` sobre entrada del usuario, el patrón de inyección más conocido de JavaScript. La etapa de SAST pasó limpia.
- **La causa:** Semgrep corría con `--config p/ci --config p/dockerfile`, que suman **38 reglas**, ninguna de seguridad de JavaScript. El log lo decía en claro: `Ran 38 rules on 47 files: 0 findings`. Y ESLint avisó de paso que `no-eval` ni siquiera estaba activado en la configuración.
- **Cómo lo arreglé:** agregué `--config p/javascript`.
- **Qué me llevo:** tener la herramienta no es tenerla configurada. El número de reglas que corre un escáner es un dato que hay que mirar, no asumir.

### Hallazgo 3: lo barato se detecta temprano

Es lo que el enunciado quería que viera, y los números lo dicen solos: un error de estilo cuesta **24 segundos**; una vulnerabilidad en una imagen base exige construir, publicar y escanear primero, y cuesta **2 minutos y medio**. Seis veces más caro por el mismo tipo de error humano. Esa es toda la razón de ordenar el pipeline de lo barato a lo caro.

---

## Reto 1: DAST con OWASP ZAP

- **Decisión:** un *baseline scan* de ZAP 2.16.1 contra el DEV que el pipeline ya levanta dentro del runner. El informe HTML queda como artefacto del run.
- **Alternativas que evalué:**
  - *Full scan*: hace escaneo activo, es decir, ataca de verdad. Encuentra más, pero tarda mucho más y puede dejar la aplicación sucia. No cabe en una etapa de pipeline que debe durar minutos.
  - *API scan*: apunta a una especificación OpenAPI. La aplicación no publica una, y escribirla solo para esto era desviarse del objetivo.
  - *Escanear STAGING en vez de DEV*: tentador porque es el ambiente persistente, pero significaría atacar el ambiente al que ya se promovió algo. DEV es efímero y nace y muere en el job: es el lugar correcto para que una herramienta lo golpee.
- **La alerta que corregí:** la aplicación no enviaba **ninguna** cabecera de seguridad. Agregué `X-Content-Type-Options: nosniff` (que el navegador no adivine el tipo de archivo), `X-Frame-Options: DENY` (contra clickjacking), `Referrer-Policy`, una `Content-Security-Policy` que limita los recursos a los propios, y `server_tokens off` para no publicar la versión de nginx.
- **Lo que acepté, una por una, en `.zap/rules.tsv`:** Cache-Control en respuestas JSON dinámicas de la API; Permissions-Policy, porque la aplicación no usa cámara, micrófono ni geolocalización; Timestamp Disclosure, porque las "marcas de tiempo" que ZAP detecta son las fechas de publicación de los mensajes, que son públicas por diseño; y la alerta informativa de aplicación moderna.
- **Cómo lo verifiqué:** antes de subirlo, levanté la aplicación en local y corrí el mismo contenedor de ZAP: termina con código 0 y `curl -D-` muestra las cuatro cabeceras.
- **Qué aprendí:** la `Content-Security-Policy` fue la única que costó. La primera versión rompía la página porque el HTML trae un `<style>` en línea, y la política lo bloqueaba. Hubo que permitir `'unsafe-inline'` **solo para estilos**, dejando el JavaScript restringido a archivos propios. Es un buen ejemplo de que una cabecera de seguridad mal puesta rompe la aplicación en silencio.
