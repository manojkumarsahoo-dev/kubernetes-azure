#!/usr/bin/env bash
# Creates the "backend-secret" Kubernetes Secret in the "microservices" namespace.
#
# Required: DB_PASSWORD (the same value as the MYSQL_ADMIN_PASSWORD GitHub secret) and Mail credentials.
# DB_HOST and DB_USER are looked up automatically; override them with env vars if needed.
#
#   DB_PASSWORD='...' MAIL_USERNAME=you@gmail.com MAIL_PASSWORD='app password' ./scripts/create-backend-secret.sh
set -euo pipefail

NS="${NAMESPACE:-microservices}"
RG="${RESOURCE_GROUP:-${AZURE_RESOURCE_GROUP:-${TF_VAR_resource_group_name:-}}}"
if [ -z "$RG" ]; then
  echo "Set RESOURCE_GROUP to the existing Azure sandbox resource group."
  exit 1
fi

DB_HOST="${DB_HOST:-$(az mysql flexible-server list --resource-group "$RG" --query "[0].fullyQualifiedDomainName" -o tsv)}"
DB_USER="${DB_USER:-shopadmin}"

if [ -z "$DB_HOST" ]; then echo "Could not find the MySQL server in resource group $RG"; exit 1; fi
if [ -z "${DB_PASSWORD:-}" ]; then read -r -s -p "MySQL admin password: " DB_PASSWORD; echo; fi
if [ -z "${MAIL_USERNAME:-}" ]; then read -r -p "Mail username (Gmail address): " MAIL_USERNAME; fi
if [ -z "${MAIL_PASSWORD:-}" ]; then read -r -s -p "Mail password (Gmail app password): " MAIL_PASSWORD; echo; fi

# Gmail app passwords are 16 letters shown in groups of four. Strip spaces and any <> copied by mistake,
# otherwise Gmail rejects the login ("Connection unexpectedly closed").
MAIL_PASSWORD="$(printf '%s' "$MAIL_PASSWORD" | tr -d '[:space:]<>')"
if [ "${#MAIL_PASSWORD}" -ne 16 ]; then
  echo "Warning: MAIL_PASSWORD is ${#MAIL_PASSWORD} characters; a Gmail app password is normally 16." >&2
fi

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic backend-secret \
  --namespace "$NS" \
  --from-literal=DB_HOST="$DB_HOST" \
  --from-literal=DB_USER="$DB_USER" \
  --from-literal=DB_PASSWORD="$DB_PASSWORD" \
  --from-literal=MAIL_USERNAME="$MAIL_USERNAME" \
  --from-literal=MAIL_PASSWORD="$MAIL_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secret backend-secret created/updated in namespace $NS (DB host: $DB_HOST)"
echo "Pods read the Secret only at start-up. Now run:"
echo "  kubectl rollout restart deployment backend-deployment -n $NS"
