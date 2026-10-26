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

La tabla job por job está en el README. Lo que mido es el **camino crítico hasta poder mezclar**: desde que arranca el primer job hasta que acaba el último de los diez que protegen `main`. Es el tiempo que alguien espera de verdad mirando el PR, y es lo que hace que un pipeline se respete o se ignore.

| | Run | Camino crítico |
|---|---|---|
| Primer run completo en verde | [40247656671](https://github.com/Gabrieldla/demo-cicd/actions/runs/40247656671) | **153 s** |
| Después de optimizar | [40261275154](https://github.com/Gabrieldla/demo-cicd/actions/runs/40261275154) | **95 s** |

Son **−38 %**, por encima del 25 % que pedía el criterio. Lo que más me sorprendió es de dónde salió la mejora: **casi toda del grafo, no de las cachés**. Se ve en el minuto en que cada etapa *arranca*, no en lo que dura:

| Etapa | Arrancaba en | Arranca en |
|---|---|---|
| 3. Pruebas unitarias | +18 s (esperando a `lint`) | **+1 s** |
| 4. Integración | +31 s | **+15 s** |
| 5. Empaquetar | +72 s (esperando a integración) | **+26 s** |
| 6. Escaneo de imagen | +121 s | **+63 s** |

- `test-unit` esperaba a `lint` sin ninguna razón: un error de estilo no invalida una prueba, ni una prueba rota se arregla formateando.
- `package` esperaba a `test-integration`, y eso era lo caro: **46 segundos de cola** antes de empezar a construir. Pero **publicar una imagen no es desplegarla**: si la integración falla, la compuerta de DEV lo frena igual, porque `deploy-dev` necesita a las dos. Lo único que se pierde en ese caso es una imagen publicada que nadie usa, y eso es más barato que 46 segundos en cada run.

Las cachés también ayudaron —`package (api)` bajó de 47 s a 23 s con la caché de capas de Docker—, pero el salto grande vino de dejar de hacer cola donde no hacía falta. La pregunta útil no es "¿cómo hago cada paso más rápido?", sino "¿qué está esperando a qué, y por qué?".

**Una honestidad sobre los números:** los primeros que escribí aquí (155 s → 86 s) no los pude reproducir desde la pestaña Actions, y los cambié por los dos runs de arriba, que sí se pueden abrir y comprobar. El runner alojado varía bastante de un run a otro: el mismo pipeline, sin tocar nada, me ha dado entre 95 s y 104 s. Por eso lo que vale es el cambio en el **momento de arranque** de cada etapa, que depende del grafo y no de la suerte, y no el total al segundo.

---

## Hallazgo 5: probé el escáner de secretos y descubrí qué *no* reporta

Antes de dar por bueno el cambio de Gitleaks a TruffleHog quise comprobar que la etapa 2 frena de verdad, igual que hice con las otras cuatro. Armé un repositorio de prueba con cinco credenciales falsas: una llave de AWS, un webhook de Slack, un token personal de GitHub, una cadena de conexión de Postgres y la clave secreta de AWS.

TruffleHog reportó **una sola**: la de Postgres.

```
Detector Type: Postgres        → reportada
AWS, Slack, GitHub PAT         → silencio
unverified_secrets: 1
```

No es un fallo del escáner, es `--results=verified,unknown` haciendo exactamente lo que le pedí, y vale la pena entender por qué:

- Para AWS, Slack y GitHub, TruffleHog **preguntó al emisor** si la credencial existe. Los tres respondieron que no. Eso la clasifica como `unverified` —muerta, comprobado— y el filtro la descarta. Una llave revocada no es un incidente.
- Para la de Postgres **no pudo preguntar**: el host `db.staging.interno` no resuelve. Sin respuesta no hay veredicto, así que cae en `unknown`, y `unknown` sí pasa el filtro.

Lo importante es hacia dónde falla cuando no sabe: **reporta**. Si mañana el runner se queda sin salida a internet, la verificación empieza a dar error en todo y el escáner se vuelve más ruidoso, no más silencioso. Es el lado correcto para equivocarse.

Y confirma lo que escribí al elegir la herramienta, que entonces era solo una intuición: si dejara `--results=verified` a secas, la credencial de Postgres —la única real de las cinco, la que apunta a mi propia base— **no se habría reportado**, porque TruffleHog no tiene forma de verificarla. El filtro por defecto habría dejado pasar justo la que importaba.

**Qué me llevo:** un escáner de secretos no se configura, se calibra. Y la única forma de saber qué deja pasar es darle secretos de prueba y mirar cuáles no aparecen, porque los que no aparecen no dejan rastro en ningún log.

---

## Hallazgo 6: el escáner de secretos miraba ramas que no eran la mía

El PR de esta misma bitácora, que **solo toca archivos `.md`**, falló en la etapa de secretos:

```
Detector Type: Postgres
File: api/server.js
Line: 11
exit code 183
```

`api/server.js` no está tocado en ese PR. Esa línea vive en `romper/5-secreto`, otra rama.

La causa es que `trufflehog git file:///repo` recorre **todas las ramas del repositorio**, no la que el runner tiene desplegada. Y con `fetch-depth: 0`, puesto justo para que el escaneo vea el historial completo, el runner se trae todas. Así que una rama con un secreto a propósito ponía la etapa 2 en rojo **en cualquier rama, para siempre**. Y las cinco ramas `romper/*` están abiertas a propósito: son la evidencia del B3.

Lo arreglé apuntando el escaneo al historial alcanzable desde lo que se va a mezclar. No es aflojar la compuerta, es hacerle la pregunta correcta: *¿esto que voy a integrar trae un secreto?*

**Lo que me costó decidir** fue si eso era hacer trampa. Lo pensé así: un secreto empujado a cualquier rama **está filtrado de verdad**, y eso no se arregla borrando la rama ni cambiando el escáner, se arregla **rotando la credencial**. Lo que sí se arregla aquí es que la compuerta pueda volver a ponerse verde. Una compuerta que está en rojo pase lo que pase no frena nada: a los dos días alguien la desactiva, o peor, aprende a ignorar el rojo. Eso es más peligroso que el secreto original.

Y hay una consecuencia que no había pensado: **un secreto no se puede "arreglar" con un commit encima**. Las otras cuatro roturas vuelven a verde con un commit que deshace el daño; la del secreto no, porque sigue en el historial de su rama. Es la demostración más clara de por qué la respuesta a una credencial filtrada es rotarla y no borrarla.

---

## Hallazgo 7: la aprobación manual no era el último obstáculo

STAGING fue lo último en funcionar, y llegar ahí me costó tres intentos con tres causas distintas. Lo anoto porque la lección no es ninguna de las tres por separado.

1. **El shell.** `shell: bash` en un runner de Windows resuelve el stub de WSL (`WindowsApps\bash.EXE`) y el job muere con `execvpe(/bin/bash): No such file or directory`, porque instalé WSL sin distribución: la suya la trae Rancher Desktop. Intenté arreglarlo dando la ruta absoluta de Git Bash como shell y **salió peor**: el runner la pasa por un `Path.Combine` de .NET y revienta con `Second path fragment must not be a drive or UNC name` antes de ejecutar una sola línea. El job terminó en `shell: powershell`, que el runner de Windows resuelve siempre, invocando el ejecutable de Git Bash a mano donde hacen falta los scripts.
2. **El clúster no estaba preparado.** El namespace `demo-staging` y el Secret `db-credenciales` son paso manual **por diseño** —STAGING es persistente, no se recrea en cada run— y nunca los había creado. El pipeline no podía saberlo: `kubectl apply` contra un namespace que no existe falla, y punto.
3. **El puerto estaba ocupado.** `nodePort: 30080` lo tenía el sitio del LAB-02, que sigue corriendo en mi clúster desde hace veinticinco días. `kubectl` lo rechaza con `provided port is already allocated`. Moví STAGING a 30090 en vez de tirar el otro ambiente: mover un puerto cuesta una línea, y tirar la evidencia de otro laboratorio no se deshace.

**Qué me llevo:** las tres fallaron en el único job que corre en mi máquina, y ninguna habría aparecido en un runner de GitHub. Un ambiente que solo existe en una laptop no está probado hasta que se despliega en esa laptop, y cada intento costaba una aprobación manual mía. Después del segundo fallo dejé de adivinar y corrí a mano la secuencia completa —`desplegar.sh`, los tres `rollout status`, `smoke.sh`— hasta verla en verde en local. Recién entonces volví a pedir la aprobación. Probar en el sitio sale más barato que probar en el pipeline.

---

## Hallazgo 8: tenía un archivo inválido en rojo desde el primer día

Dependabot llevaba dos días configurado y **no había abierto un solo PR**, con cinco dependencias que tenían versión mayor nueva: `eslint` 9→10, `vitest` 2→5, `jsdom` 25→29, `globals` 15→17 y `express` 4→5.

Mi primera explicación fue el `interval: weekly`: Dependabot elige un día de la semana y hasta que no cae, no revisa. Lo pasé a `daily` —razonándolo, porque el `cooldown` ya me protege de instalar algo recién publicado— y **seguía sin abrir nada**. Ahí dejé de suponer y me puse a buscar.

Lo encontré en un sitio tonto: un check en un PR que solo tocaba archivos `.md`.

```
The property '#/updates/0/cooldown/semver-major-days' is not supported
for the package ecosystem 'github-actions'.
```

Los `semver-*-days` solo valen para ecosistemas con semver de verdad, y las acciones de GitHub no lo son. Pero lo grave no es el error, son sus dos consecuencias:

1. **Dependabot no se queja a medias: rechaza el archivo completo.** Un error en el bloque de `github-actions` dejó sin revisar también `npm` y `docker`, que tenían su `cooldown` bien puesto. Tres ecosistemas apagados por una línea.
2. **El check que lo decía no era obligatorio.** Se llama `.github/dependabot.yml`, sale en los PR, y no está entre los diez checks que protegen `main`. Llevaba dos días en rojo mientras el resto salía en verde y yo seguía mezclando. Lo vi de casualidad.

**Qué me llevo:** es la tercera vez en este laboratorio que me pasa lo mismo —la tubería sin `pipefail`, el Semgrep con 38 reglas, y ahora esto—, y por eso lo escribo como una sola lección: **tener la herramienta configurada no es tenerla funcionando, y un pipeline verde no demuestra que lo esté**. Las tres veces el sistema estaba dando señales; dos de ellas solo aparecieron cuando rompí algo a propósito, y la tercera estaba escrita en un check que nunca había abierto porque no me frenaba nada.

Lo que yo hubiera querido es que fallara. Un check que avisa pero no bloquea acaba siendo decoración: si no frena, no se lee.

### Lo que intenté después, y por qué lo deshice

La conclusión de arriba pedía una acción, así que la hice: agregué `.github/dependabot.yml` a los checks obligatorios de `main`, para que un archivo inválido frenara un merge en vez de avisar en voz baja.

**Bloqueó `main` por completo.** Ese check no lo publica mi workflow, lo publica Dependabot, y no aparece en todos los PR: en el siguiente, con los diez checks del pipeline en verde, GitHub lo dejó en `BLOCKED` esperando un contexto que nunca iba a llegar. Lo comprobé pidiendo los `check-runs` del commit: el de Dependabot no estaba.

Lo quité y `main` volvió a `CLEAN` en el mismo momento.

**Qué me llevo, que es lo contrario de lo que esperaba:** una regla de protección solo sirve si el check que exige **se publica siempre**. Exigir uno que depende de si otro sistema decide opinar sobre ese commit no endurece la rama, la deja muerta. Y lo descubrí rápido solo porque tenía un PR abierto esperando; si lo hubiera hecho con el repositorio en calma, me habría encontrado `main` inmezclable sin entender por qué.

Así que el problema del hallazgo 8 sigue sin solución automática, y prefiero decirlo a inventarme una: lo que me queda es **saber que ese check existe y mirarlo**. Que es exactamente la clase de respuesta que no me gusta, porque depende de que yo me acuerde.

---

## Lo que pasó cuando Dependabot por fin arrancó

En cuanto el archivo fue válido, Dependabot abrió **ocho PR** en unos minutos. Todas mayores, porque llevaba dos días sin revisar nada.

Lo primero que comprobé fue el `cooldown`, que es la mitad del motivo por el que puse Dependabot. Funcionó, y se ve mejor en lo que **no** propuso: a `vitest` le propuso la **5.0.5 estable**, no la `5.1.0-beta.1` que llevaba siete días publicada. Eso es exactamente lo que quería: enterarme de las versiones nuevas sin ser el primero en instalarlas.

Mezclé cuatro, todas después de pasar los doce jobs: `actions/cache` 4→6, `actions/upload-artifact` 4→7, `vitest` 2→5 y `globals` 15→17. La de `vitest` me importaba más de lo que parece: es el corredor de pruebas, y un salto de tres versiones mayores con **todas las pruebas en verde** es la señal más fuerte que puede dar un pipeline. Si el corredor se hubiera roto, las pruebas no habrían pasado, por definición.

### La que rechacé, y por qué

Dependabot propuso `node:22-alpine` → `node:25-alpine` para la imagen de la API. **Pasó los doce jobs en verde**: lint, SAST, unitarias, integración, las tres imágenes, los tres escaneos de Trivy y el smoke contra el clúster de DEV. La cerré igual.

Node numera las líneas impares como `current`: el 25 no es LTS, el 24 (Krypton) sí, y el 22 (Jod) también. Una imagen que sirve una aplicación tiene que ir sobre una LTS, porque lo que importa no es el número más alto sino hasta cuándo va a recibir parches de seguridad. Y ahí está lo que me hizo pensar: **el pipeline no tiene forma de saber eso**. Trivy mira las vulnerabilidades que hay hoy; ninguna herramienta de las que puse mira cuántos meses de soporte le quedan a la imagen base. Doce jobs en verde y la decisión seguía siendo mala.

Pero quedarme en el 22 tampoco era la respuesta: era la cómoda. El 24 es LTS y es más nuevo. Así que la PR de Dependabot terminó sirviendo igual —demostró que la aplicación es compatible hacia adelante— y la decisión fue subir al **LTS vigente**, con el `NODE_VERSION` del workflow igualado para que las pruebas corran sobre la misma versión que la imagen. Tenerlas distintas es pedir un fallo que solo aparece en producción.

Y le dejé a Dependabot un `ignore` para las líneas impares de Node, con el motivo escrito al lado, para no tener que volver a razonar esto cada vez.

**Qué me llevo:** un pipeline en verde es una condición necesaria para mezclar, no una razón suficiente. Automatiza lo que se puede comprobar; el ciclo de vida de una dependencia no es una de esas cosas. La compuerta que falta ahí sigue siendo una persona leyendo el número de versión.

### La actualización que empeoraba la seguridad

De las ocho PR de Dependabot, la de `express` 4.22.3 → 5.3.0 es la que más me hizo pensar, y la frenó Trivy:

```
body-parser (package.json)  CVE-2026-111181  HIGH  fixed
  Installed: 2.3.0     Fixed: 2.4.0, 1.20.9
```

`express@5.3.0` arrastra `body-parser@2.3.0`, con una vulnerabilidad alta **y parche disponible**. Fui a ver con qué me estaba comparando, y ahí estaba lo interesante: en `main`, con `express@4.22.3`, el árbol trae `body-parser@1.20.9`, que es exactamente la versión parcheada de la línea 1.x.

Así que la actualización **me habría movido de una dependencia parcheada a una sin parchear**. Una versión mayor más nueva, un número más alto, y menos seguro. No es lo que uno espera al actualizar, y es precisamente el escenario para el que sirve tener la etapa 6 después de la 5: escanear la imagen **ya construida**, con el árbol de dependencias resuelto de verdad, en vez de confiar en que "lo nuevo está mejor".

Lo que no hice, y me lo pensé: forzar `body-parser` 2.4.0 por debajo de express con un `overrides` de npm. Habría funcionado y me habría dejado en express 5 unos días antes, pero a cambio de mantener a mano una excepción dentro de un árbol que no controlo. No lo paga. Se queda en express 4 hasta que express 5 declare `body-parser` ^2.4.0.

**Qué me llevo:** "actualizar" y "estar más seguro" no son la misma cosa, y la única forma de notar la diferencia es que algo mire el resultado final. Si el escaneo estuviera antes de construir, o si confiara en el número de versión, esto habría entrado sin que nadie dijera nada.

---

## Hallazgo 9: el pipeline me ofrecía desplegar hacia atrás

Mezclé varios PR seguidos y se me apilaron **seis runs de `main` esperando aprobación** de STAGING, uno por commit. Mi primera reacción fue que era ruido en la pestaña Actions. No lo era.

La compuerta de STAGING es un botón por run. Con seis esperando, puedo aprobar cualquiera, en cualquier orden, y cada uno despliega **el commit que le toca**. Si los apruebo de arriba abajo, como se leen, el último despliegue que gana es el del commit **más viejo**: el ambiente acaba corriendo código anterior al que ya estaba. Y nada en el pipeline me lo iba a decir, porque cada uno de esos runs es, por separado, perfectamente válido.

Es un fallo del diseño del pipeline, no un error de operación. El job es idempotente, el despliegue es correcto, el smoke test pasa. Lo que falta es que el pipeline sepa que **un despliegue más nuevo invalida la aprobación del anterior**.

Lo arreglé con un grupo de concurrencia por ambiente: un commit nuevo cancela la aprobación pendiente del anterior, así que solo se puede aprobar lo último. Y ahí sí cancelo —a diferencia del grupo del workflow, donde en `main` no toco nada en curso—, porque lo que se cancela es **una espera**, no un trabajo a medias.

Los seis que ya estaban apilados los cancelé a mano: aparecen como *cancelled* en el historial y es deliberado, son despliegues que quedaron obsoletos antes de ocurrir.

**Qué me llevo:** el enunciado me hizo pensar la aprobación manual como una compuerta de seguridad, y lo es. Pero una aprobación es también una cola, y una cola sin orden es una forma elegante de hacer las cosas en el orden equivocado. "Esperando que alguien decida" no es un estado neutro: cuanto más dura, más caras son las decisiones que se pueden tomar mal.
