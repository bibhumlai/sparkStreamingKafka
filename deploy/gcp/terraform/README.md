# GCP Compute Engine deployment with Terraform

This Terraform package provisions a single GCP Compute Engine VM for the existing Airflow + Spark + Aiven project.

It creates:

- one Ubuntu 22.04 VM
- one reserved external IP
- one dedicated service account
- firewall rules for SSH and the Airflow UI
- two Secret Manager secrets
- a startup script that installs Docker, clones the GitHub repo, pulls secrets, and runs `docker compose up --build -d`

## Where this Terraform stores state

The backend is already configured to use:

- bucket: `terraform-state-bibhu`
- prefix: `spark`

That means the bucket must already exist before you run `terraform init`.

## Secrets expected by the VM

The startup script reads two Secret Manager secrets:

- `spark-airflow-aiven-env`
- `spark-airflow-aiven-aiven-ca-pem`

The `.env` secret should contain the full application environment file. Use [D:\DE\Spark Streaming\.env.gcp.example](D:\DE\Spark%20Streaming\.env.gcp.example) as the template.

## Files added here

- `versions.tf`: Terraform version, provider, and backend
- `main.tf`: VM, firewall, service account, static IP, and Secret Manager resources
- `variables.tf`: configurable inputs
- `outputs.tf`: useful connection outputs
- `terraform.tfvars.example`: starter values for your project
- `templates/startup.sh.tpl`: bootstraps Docker and the app on the VM

## Deploy steps

1. Authenticate Terraform against GCP.
   - `gcloud auth application-default login`

2. Copy the example variables file.
   - `Copy-Item terraform.tfvars.example terraform.tfvars`

3. Edit `terraform.tfvars`.
   - Replace placeholder secrets.
   - If your browser or SSH client reaches the internet over IPv4 instead of IPv6, add your IPv4 address as another `/32` entry in `admin_source_ranges`.

4. Initialize Terraform.
   - `terraform init`

5. Review the plan.
   - `terraform plan`

6. Apply the infrastructure.
   - `terraform apply`

7. After the VM is up, use the output Airflow URL.
   - By default this will be `http://<vm-external-ip>:8088`

## Notes

- The current Docker Compose stack still runs everything on one VM, which is the lowest-friction move from your local setup.
- The VM startup script installs Docker, clones the repo, fetches Secret Manager values, marks the repo as a safe Git directory, and fixes Airflow log/output permissions before starting containers.
- If the Airflow URL times out even though containers are healthy, add your current public IPv4 address as another `/32` in `admin_source_ranges` and re-apply Terraform.
- If you do not want secrets stored in Terraform state, leave the secret payload variables empty and add secret versions manually in GCP after the secrets are created.

## Optional GitHub Actions auto-deploy

The repo now includes [D:\DE\Spark Streaming\.github\workflows\deploy-gcp-vm.yml](D:\DE\Spark%20Streaming\.github\workflows\deploy-gcp-vm.yml), which SSHes into the VM and runs [D:\DE\Spark Streaming\deploy\gcp\scripts\redeploy.sh](D:\DE\Spark%20Streaming\deploy\gcp\scripts\redeploy.sh) whenever code is pushed to `main`.

Add these GitHub repository secrets before enabling that workflow:

- `GCP_VM_HOST`
- `GCP_VM_USER`
- `GCP_VM_SSH_PRIVATE_KEY`
