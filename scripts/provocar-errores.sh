#!/usr/bin/env bash
# Provoca errores 5xx de verdad en STAGING para comprobar que la alerta salta.
#
# No le pego a una ruta que no existe, porque eso da 404 y un 404 no es un error
# del servidor: es el servidor funcionando. Lo que simulo es una caída de la base
# de datos, que es el 5xx que de verdad me puede pasar: la API sigue en pie,
# acepta la petición y falla al consultar.
#
# Uso: scripts/provocar-errores.sh [segundos]
set -euo pipefail

SEGUNDOS=${1:-150}
URL=${URL:-http://localhost:30090}

echo "==> Tumbando la base de datos de STAGING (se levanta al final)"
kubectl -n demo-staging scale deploy/db --replicas=0
trap 'echo; echo "==> Levantando la base de datos"; kubectl -n demo-staging scale deploy/db --replicas=1; kubectl -n demo-staging rollout status deploy/db --timeout=180s' EXIT

# Sin esto, la API puede tener la conexión aún viva en el pool y responder bien.
sleep 10

echo "==> Pegándole a $URL/api/mensajes durante $SEGUNDOS s"
fin=$(( $(date +%s) + SEGUNDOS ))
total=0; errores=0
while [ "$(date +%s)" -lt "$fin" ]; do
  codigo=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL/api/mensajes" || echo 000)
  total=$((total + 1))
  case "$codigo" in 5*) errores=$((errores + 1)) ;; esac
  printf '\r    %d peticiones, %d con 5xx' "$total" "$errores"
  sleep 0.4
done
echo

echo "==> Mira la alerta en:"
echo "    http://localhost:30091/alerts     (TasaDeErrores5xxAlta, debe estar FIRING)"
echo "    http://localhost:30093            (Alertmanager)"
