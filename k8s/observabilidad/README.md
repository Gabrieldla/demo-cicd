# Observabilidad en STAGING (Reto 3)

Prometheus, Alertmanager y Grafana en el clúster, vigilando el STAGING que el pipeline despliega.

## Cómo levantarlo

```bash
scripts/desplegar-observabilidad.sh
```

| | |
|---|---|
| Grafana | http://localhost:30092 — dashboard *Libro de visitas: métricas RED* |
| Prometheus | http://localhost:30091 — *Status → Targets*, y *Alerts* |
| Alertmanager | http://localhost:30093 |

## Por qué no usé `kube-prometheus-stack`

Es lo que recomienda el enunciado, y lo descarté por una razón medida, no por comodidad: mi clúster es un Rancher Desktop de un solo nodo que ya está **al 80 % de memoria** con la aplicación corriendo (`kubectl top nodes`: 6282Mi de 7.8Gi). Ese chart trae además node-exporter, kube-state-metrics, el operador de Prometheus y sus CRD. Lo que necesito son tres procesos y una regla.

También pesa que el clúster es **k3s v1.25**, bastante por detrás de lo que piden las versiones recientes del chart.

El coste de la decisión es real y lo asumo: no tengo métricas del nodo ni del propio Kubernetes, solo de la aplicación. Para una alerta sobre la tasa de error de la API, alcanza.

## Lo que cambió respecto de Compose

En Compose, Prometheus tenía la lista escrita a mano:

```yaml
static_configs:
  - targets: ["api:3000"]
```

En Kubernetes eso no sirve: los pods cambian de IP en cada despliegue y la API tiene dos réplicas. Se descubren **por anotación** — el Deployment de la API ya traía `prometheus.io/scrape`, `/port` y `/path` — preguntándole a la API de Kubernetes. Prometheus tiene un ServiceAccount con permiso de **solo lectura** sobre pods, services y endpoints: no puede crear ni borrar nada.

Añadir una réplica, o desplegar otro servicio con las mismas anotaciones, no obliga a tocar ningún archivo.

## La alerta, y su prueba

`reglas/api.yml` tiene una regla: **más del 5 % de respuestas 5xx durante un minuto**.

Lo que me costó no fue el umbral, fue el caso sin tráfico. La expresión divide los errores entre el total de peticiones, y sin tráfico eso es `0/0 = NaN`: una regla mal escrita se queda callada para siempre, o grita sin motivo, y eso **no se nota mirando una gráfica un rato**. Por eso la condición es explícita: hay peticiones **y** más del 5 % fallan.

Y por eso la regla tiene pruebas, que corren en el pipeline (etapa 3):

```bash
docker run --rm -v "$PWD/k8s/observabilidad/reglas:/r" -w /r \
  --entrypoint promtool prom/prometheus:v3.15.1 \
  test rules pruebas-alertas.yml
```

Tres casos:

1. 17 % de 5xx → **a los 30 s no dispara** (el `for: 1m` evita avisar por un pico de tres segundos) y **a los 2 min sí**, con el valor real en la anotación: `16.67%`.
2. 2 % de 5xx → no dispara. No todo error es una incidencia.
3. Sin tráfico → no dispara.

`reglas/api.yml` es la **única** copia de la regla: el ConfigMap que Prometheus monta lo genera el script a partir de este archivo, y las pruebas leen el mismo. Igual que el dashboard, que sale del JSON que ya usaba Compose.

## Cómo comprobar que salta de verdad

```bash
scripts/provocar-errores.sh
```

No le pega a una ruta que no existe, porque eso da **404**, y un 404 no es un error del servidor: es el servidor funcionando. El script tumba la base de datos de STAGING y pide `/api/mensajes`: la API sigue en pie, acepta la petición y falla al consultar. Ese es el 5xx que de verdad puede pasar. Al terminar, levanta la base.

## La pregunta de la bitácora

> ¿Qué métrica agregarías a la API para saber si la base de datos se está volviendo lenta?

Un histograma del tiempo de cada consulta, `db_query_duration_seconds`, con etiqueta por operación (`select_mensajes`, `insert_mensaje`, `count_mensajes`), midiendo alrededor de cada `pool.query`.

El `http_request_duration_seconds` que ya existe **no sirve** para esto: mezcla el tiempo de la base con el de Express, el del parseo y el de la red, así que cuando sube no dice dónde está el problema. Con los dos, la resta es el diagnóstico: si el p95 de la petición sube y el de la consulta no, el problema es la aplicación; si suben los dos a la vez, es la base.

Y añadiría dos del pool, que son las que avisan **antes** de que se note: `db_pool_esperando` (peticiones encoladas esperando una conexión libre) y `db_pool_conexiones_activas`. Una base que se vuelve lenta primero llena el pool y recién después empieza a devolver errores. Cuando el usuario ve un 500, el aviso llegó tarde.
