#!/usr/bin/env bash
# Levanta Prometheus, Alertmanager y Grafana en el clúster, vigilando STAGING.
#
# No uso kube-prometheus-stack (el chart de Helm que recomienda el enunciado) por
# una razón concreta: mi clúster es un Rancher Desktop de un solo nodo que ya está
# al 80 % de memoria con la aplicación corriendo, y ese chart trae además
# node-exporter, kube-state-metrics, el operador y sus CRD. Lo que necesito son
# tres procesos y una regla. Está explicado en la bitácora.
#
# Uso: scripts/desplegar-observabilidad.sh
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Manifiestos"
# Solo esta carpeta, que NO es recursiva: los .yml de reglas/ no son manifiestos de
# Kubernetes y kubectl los rechazaria con "apiVersion not set, kind not set".
# Por eso viven en un subdirectorio y no sueltos aqui.
kubectl apply -f k8s/observabilidad/00-namespace.yaml
kubectl apply -f k8s/observabilidad/

# Las reglas viven en k8s/observabilidad/reglas/api.yml y de ahi salen dos
# cosas: este ConfigMap y las pruebas de promtool. Una sola copia.
echo "==> Reglas de alerta (desde k8s/observabilidad/reglas/api.yml)"
kubectl -n observabilidad create configmap prometheus-reglas   --from-file=api.yml=k8s/observabilidad/reglas/api.yml   --dry-run=client -o yaml | kubectl apply -f -

# El dashboard se genera a partir del MISMO archivo que usa Compose. Tener dos
# copias del JSON es garantizar que una se queda vieja.
echo "==> Dashboard RED (desde observabilidad/grafana/...)"
kubectl -n observabilidad create configmap grafana-dashboards \
  --from-file=libro-de-visitas.json=observabilidad/grafana/provisioning/dashboards/libro-de-visitas.json \
  --dry-run=client -o yaml | kubectl apply -f -

# Si el ConfigMap cambió, Grafana ya está corriendo con el viejo montado: el
# kubelet actualiza el archivo pero Grafana no lo relee solo.
kubectl -n observabilidad rollout restart deploy/grafana
# Prometheus relee las reglas sin reiniciar, por el --web.enable-lifecycle.
kubectl -n observabilidad rollout restart deploy/prometheus

echo "==> Esperando"
kubectl -n observabilidad rollout status deploy/prometheus   --timeout=180s
kubectl -n observabilidad rollout status deploy/alertmanager --timeout=180s
kubectl -n observabilidad rollout status deploy/grafana      --timeout=180s

cat <<TEXTO

Listo.

  Grafana       http://localhost:30092   (dashboard "Libro de visitas: métricas RED")
  Prometheus    http://localhost:30091   (Status -> Targets, y Alerts)
  Alertmanager  http://localhost:30093

Para comprobar que la alerta salta, sin inventar métricas:

  scripts/provocar-errores.sh

TEXTO
