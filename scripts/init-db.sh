#!/usr/bin/env bash
# Loads backend/test.sql into Azure Database for MySQL from inside the cluster.
# (The server is private, so it cannot be reached from your laptop.)
#
# WARNING: test.sql DROPs and recreates the tables. Only run it on a fresh database.
# Requires the "backend-secret" Secret to exist (scripts/create-backend-secret.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NS="${NAMESPACE:-microservices}"

kubectl create configmap db-init-sql \
  --namespace "$NS" \
  --from-file=test.sql="$ROOT/backend/test.sql" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl delete job db-init --namespace "$NS" --ignore-not-found
kubectl apply -f "$ROOT/db-init/db-init-job.yml"

kubectl wait --for=condition=complete job/db-init --namespace "$NS" --timeout=180s
kubectl logs job/db-init --namespace "$NS"
echo "Database initialised."
