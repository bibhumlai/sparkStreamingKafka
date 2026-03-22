#!/bin/bash
set -euxo pipefail

exec > >(tee /var/log/spark-airflow-aiven-startup.log | logger -t spark-airflow-aiven-startup -s 2>/dev/console) 2>&1

export DEBIAN_FRONTEND=noninteractive
export HOME=/root

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl docker.io docker-compose git python3
systemctl enable --now docker
usermod -aG docker ${ssh_username} || true

mkdir -p ${app_directory}
chown -R ${ssh_username}:${ssh_username} ${app_directory}

if [ ! -d "${app_directory}/.git" ]; then
  git clone --branch "${repo_branch}" "${repo_url}" "${app_directory}"
else
  git -C "${app_directory}" fetch --all --prune
  git -C "${app_directory}" checkout "${repo_branch}"
git -C "${app_directory}" reset --hard "origin/${repo_branch}"
fi

mkdir -p "${app_directory}/secrets" "${app_directory}/output" "${app_directory}/airflow/logs"
chmod 755 "${app_directory}/secrets"
chown -R 50000:0 "${app_directory}/airflow/logs" "${app_directory}/output"
chmod -R ug+rwX "${app_directory}/airflow/logs" "${app_directory}/output"
git config --system --add safe.directory "${app_directory}"

fetch_secret() {
  local secret_name="$1"
  local access_token

  access_token="$(curl -fsS -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | \
    python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')"

  curl -fsS -H "Authorization: Bearer $${access_token}" \
    "https://secretmanager.googleapis.com/v1/projects/${gcp_project_id}/secrets/$${secret_name}/versions/latest:access" | \
    python3 -c 'import base64,json,sys; print(base64.b64decode(json.load(sys.stdin)["payload"]["data"]).decode("utf-8"), end="")'
}

fetch_secret "${env_secret_id}" > "${app_directory}/.env"
fetch_secret "${ca_secret_id}" > "${app_directory}/secrets/aiven-ca.pem"
chmod 600 "${app_directory}/.env"
chmod 644 "${app_directory}/secrets/aiven-ca.pem"

if ! grep -q '^AIRFLOW_BASE_URL=' "${app_directory}/.env"; then
%{ if airflow_base_url != null ~}
  echo "AIRFLOW_BASE_URL=${airflow_base_url}" >> "${app_directory}/.env"
%{ else ~}
  external_ip="$(curl -fsS -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip")"
  echo "AIRFLOW_BASE_URL=http://$${external_ip}:8088" >> "${app_directory}/.env"
%{ endif ~}
fi

cat > /usr/local/bin/spark-airflow-aiven-refresh.sh <<'EOF'
#!/bin/bash
set -euo pipefail

APP_DIR="${app_directory}"
REPO_BRANCH="${repo_branch}"

git config --system --add safe.directory "$${APP_DIR}"

if [ -d "$${APP_DIR}/.git" ]; then
  git -C "$${APP_DIR}" fetch --all --prune
  git -C "$${APP_DIR}" checkout "$${REPO_BRANCH}"
  git -C "$${APP_DIR}" reset --hard "origin/$${REPO_BRANCH}"
fi
EOF
chmod +x /usr/local/bin/spark-airflow-aiven-refresh.sh

cat > /etc/systemd/system/spark-airflow-aiven.service <<EOF
[Unit]
Description=Spark Airflow Aiven Docker stack
After=docker.service network-online.target
Wants=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${app_directory}
ExecStartPre=/usr/local/bin/spark-airflow-aiven-refresh.sh
ExecStart=/usr/bin/docker-compose up --build -d
ExecStop=/usr/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now spark-airflow-aiven.service
