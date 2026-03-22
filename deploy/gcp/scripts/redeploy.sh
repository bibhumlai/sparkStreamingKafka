#!/bin/bash
set -euxo pipefail

APP_DIR="${1:-/opt/spark-airflow-aiven-local}"
REPO_BRANCH="${REPO_BRANCH:-main}"
ENV_SECRET_ID="${ENV_SECRET_ID:-spark-airflow-aiven-env}"
CA_SECRET_ID="${CA_SECRET_ID:-spark-airflow-aiven-aiven-ca-pem}"
PROJECT_ID="${GCP_PROJECT_ID:-$(curl -fsS -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/project/project-id")}"

cd "${APP_DIR}"

git config --system --add safe.directory "${APP_DIR}"
git fetch --all --prune
git checkout "${REPO_BRANCH}"
git reset --hard "origin/${REPO_BRANCH}"

mkdir -p "${APP_DIR}/secrets" "${APP_DIR}/output" "${APP_DIR}/airflow/logs"
chmod 755 "${APP_DIR}/secrets"
chown -R 50000:0 "${APP_DIR}/airflow/logs" "${APP_DIR}/output"
chmod -R ug+rwX "${APP_DIR}/airflow/logs" "${APP_DIR}/output"

fetch_secret() {
  local secret_name="$1"
  local access_token

  access_token="$(curl -fsS -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | \
    python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')"

  curl -fsS -H "Authorization: Bearer ${access_token}" \
    "https://secretmanager.googleapis.com/v1/projects/${PROJECT_ID}/secrets/${secret_name}/versions/latest:access" | \
    python3 -c 'import base64,json,sys; print(base64.b64decode(json.load(sys.stdin)["payload"]["data"]).decode("utf-8"), end="")'
}

fetch_secret "${ENV_SECRET_ID}" > "${APP_DIR}/.env"
fetch_secret "${CA_SECRET_ID}" > "${APP_DIR}/secrets/aiven-ca.pem"
chmod 600 "${APP_DIR}/.env"
chmod 644 "${APP_DIR}/secrets/aiven-ca.pem"

if ! grep -q '^AIRFLOW_BASE_URL=' "${APP_DIR}/.env"; then
  external_ip="$(curl -fsS -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip")"
  echo "AIRFLOW_BASE_URL=http://${external_ip}:8088" >> "${APP_DIR}/.env"
fi

docker-compose down --remove-orphans || true
docker-compose up --build -d
