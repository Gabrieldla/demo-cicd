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

Es lo que el enunciado quería que viera, y los números lo dicen solos: un error de estilo cuesta **23 segundos**; una vulnerabilidad en una imagen base exige construir, publicar y escanear primero, y cuesta **2 minutos y medio**. Seis veces más caro por el mismo tipo de error humano. Esa es toda la razón de ordenar el pipeline de lo barato a lo caro.

---

## Reto 1: DAST con OWASP ZAP

- **Decisión:** un *baseline scan* de ZAP 2.16.1 contra el DEV que el pipeline ya levanta dentro del runner. El informe HTML queda como artefacto del run.
- **Alternativas que evalué:**
  - *Full scan*: hace escaneo activo, es decir, ataca de verdad. Encuentra más, pero tarda mucho más y puede dejar la aplicación sucia. No cabe en una etapa de pipeline que debe durar minutos.
  - *API scan*: apunta a una especificación OpenAPI. La aplicación no publica una, y escribirla solo para esto era desviarse del objetivo.
  - *Escanear STAGING en vez de DEV*: tentador porque es el ambiente persistente, pero significaría atacar el ambiente al que ya se promovió algo. DEV es efímero y nace y muere en el job: es el lugar correcto para que una herramienta lo golpee.
- **La alerta que corregí:** la aplicación no enviaba **ninguna** cabecera de seguridad. Agregué `X-Content-Type-Options: nosniff` (que el navegador no adivine el tipo de archivo), `X-Frame-Options: DENY` (contra clickjacking), `Referrer-Policy`, una `Content-Security-Policy` que limita los recursos a los propios, y `server_tokens off` para no publicar la versión de nginx.
- **Lo que acepté, una por una, en `.zap/rules.tsv`:** seis alertas, cada una con su motivo escrito al lado. Cache-Control en respuestas JSON dinámicas de la API; Permissions-Policy, porque la aplicación no usa cámara, micrófono ni geolocalización; Timestamp Disclosure, porque las "marcas de tiempo" que ZAP detecta son las fechas de publicación de los mensajes, que son públicas por diseño; la alerta informativa de aplicación moderna; y las dos últimas, que aparecieron recién al correr en DEV, están explicadas al final de esta bitácora.
- **Cómo lo verifiqué:** antes de subirlo, levanté la aplicación en local y corrí el mismo contenedor de ZAP: termina con código 0 y `curl -D-` muestra las cabeceras en la respuesta real.
- **Qué aprendí:** la `Content-Security-Policy` fue la única que costó, y por un motivo que no esperaba. La escribí con `'unsafe-inline'` en `style-src` dando por hecho que el HTML traía estilos en línea; no los trae, todo viene de `estilos.css`. Es decir, debilité la política para resolver un problema que no existía, y la cabecera siguió pareciendo correcta. Lo descubrí después, en DEV, y está contado en la sección final. Una cabecera de seguridad mal puesta no avisa: o rompe la página en silencio, o —peor— no protege y se ve igual de bien.

---

## Hallazgo 4: el SAST no busca `eval`, busca `eval` alimentado por el usuario

Al preparar la rotura del SAST escribí esto, convencido de que cualquier escáner lo marcaría:

```js
export function calcular(expresionDelUsuario) {
  return eval(expresionDelUsuario);
}
```

Pasó limpio. Y no solo con la configuración de la guía: probé en local `p/javascript`, `p/security-audit` y `p/owasp-top-ten`, y **ninguna** lo reportó.

La razón es que las reglas serias de Semgrep son de **análisis de contaminación** (*taint analysis*): no buscan una función peligrosa suelta, buscan un camino desde una **fuente no confiable** hasta un **destino peligroso**. Un parámetro de función no es una fuente reconocida; podría venir de cualquier parte, incluso de código propio.

Cuando reescribí la rotura como lo que de verdad sería una vulnerabilidad —una ruta de Express que evalúa lo que llega en la URL— saltó de inmediato:

```js
rutasInseguras.get("/api/calcular", (req, res) => {
  const resultado = eval(req.query.expresion);   // ← p/javascript: code-string-concat
  res.json({ resultado });
});
```

**Qué me llevo:** un SAST que no reporta nada puede significar dos cosas muy distintas: que el código está limpio, o que le estoy dando a probar algo que no se parece a una vulnerabilidad real. La única forma de saber cuál de las dos es, es meterle una vulnerabilidad de verdad y comprobar que la encuentra. Un escáner sin probar es una suposición.

## Reto 1, continuación: los avisos que aparecieron solo en DEV

El escaneo de ZAP pasó limpio en mi máquina contra Compose, y después puso `deploy-dev` en rojo con **4 avisos** al correr contra el clúster. Mismo código, mismo ZAP, resultado distinto: en DEV el escáner recorrió más rutas y vio respuestas que en local no había visitado.

De los cuatro, **dos eran arreglos reales**:

- **90004, aislamiento contra Spectre**: faltaban `Cross-Origin-Opener-Policy`, `Cross-Origin-Resource-Policy` y `Cross-Origin-Embedder-Policy`.
- **10055, CSP incompleta**: faltaba `form-action 'self'`. Y revisando eso encontré algo peor que había hecho yo: puse `'unsafe-inline'` en `style-src` "por si acaso", y resulta que **el HTML no tiene ni un estilo en línea**, todo viene de `estilos.css`. Estaba debilitando la política para nada. Lo quité.

Los otros dos se aceptan en `.zap/rules.tsv` con su motivo: el contenido estático **debe** poder cachearse (10049), y "ZAP está desactualizado" (10116) habla del escáner, no de la aplicación, y su versión está fija a propósito para que el pipeline sea reproducible.

Resultado final: **0 fallos y 0 avisos**, 63 comprobaciones pasadas y 4 aceptadas a conciencia.

## B6: dónde estaba realmente el tiempo

| | Jobs | Duración |
|---|---|---|
| Primer run completo en verde | 10 | **155 s** |
| Después de optimizar | 10 | **86 s** |

Son **−44 %**, bastante por encima del 25 % que pedía el criterio. Lo que más me sorprendió es de dónde salió la mejora: **casi toda del grafo, no de las cachés**.

- `test-unit` esperaba a `lint` sin ninguna razón: un error de estilo no invalida una prueba, ni una prueba rota se arregla formateando.
- `package` esperaba a `test-integration`, 35 segundos del camino crítico. Pero **publicar una imagen no es desplegarla**: si la integración falla, la compuerta de DEV lo frena igual, porque `deploy-dev` necesita a las dos. Lo único que se pierde en ese caso es una imagen publicada que nadie usa, y eso es más barato que 35 segundos en cada run.

Las cachés (capas de Docker y base de datos de Trivy) ayudaron, pero el salto grande vino de dejar de hacer cola donde no hacía falta. La pregunta útil no es "¿cómo hago cada paso más rápido?", sino "¿qué está esperando a qué, y por qué?".
