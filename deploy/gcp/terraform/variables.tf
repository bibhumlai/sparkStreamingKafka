variable "gcp_project_id" {
  type        = string
  description = "GCP project ID that will host the Compute Engine VM and secrets."
}

variable "gcp_region" {
  type        = string
  description = "GCP region for regional resources."
  default     = "us-central1"
}

variable "gcp_zone" {
  type        = string
  description = "GCP zone for the Compute Engine instance."
  default     = "us-central1-a"
}

variable "vm_name" {
  type        = string
  description = "Name of the Compute Engine VM."
  default     = "spark-airflow-aiven-vm"
}

variable "machine_type" {
  type        = string
  description = "Compute Engine machine type."
  default     = "e2-standard-4"
}

variable "boot_disk_size_gb" {
  type        = number
  description = "Boot disk size in GB."
  default     = 50
}

variable "boot_disk_type" {
  type        = string
  description = "Boot disk type."
  default     = "pd-balanced"
}

variable "ssh_username" {
  type        = string
  description = "Linux username that will receive the provided SSH public key."
  default     = "bibhu"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key content for VM access."
}

variable "admin_source_ranges" {
  type        = list(string)
  description = "CIDR ranges allowed to reach SSH and exposed application ports."
}

variable "airflow_ui_source_ranges" {
  type        = list(string)
  description = "CIDR ranges allowed to access the Airflow UI."
  default     = []
}

variable "open_tcp_ports" {
  type        = list(string)
  description = "TCP ports exposed by the VM firewall for the application."
  default     = ["8088"]
}

variable "network_name" {
  type        = string
  description = "VPC network name to attach to."
  default     = "default"
}

variable "subnetwork_name" {
  type        = string
  description = "Optional subnetwork name in the selected region."
  default     = null
}

variable "repo_url" {
  type        = string
  description = "Git repository URL to clone on the VM."
  default     = "https://github.com/bibhumlai/sparkStreamingKafka.git"
}

variable "repo_branch" {
  type        = string
  description = "Git branch to deploy on the VM."
  default     = "main"
}

variable "app_directory" {
  type        = string
  description = "Directory on the VM where the repo will be cloned."
  default     = "/opt/spark-airflow-aiven-local"
}

variable "airflow_base_url" {
  type        = string
  description = "Optional externally reachable Airflow base URL. Leave null to auto-generate from the VM external IP."
  default     = null
}

variable "service_account_name" {
  type        = string
  description = "Service account ID for the VM."
  default     = "spark-airflow-aiven-vm"
}

variable "labels" {
  type        = map(string)
  description = "Optional labels to apply to created resources."
  default = {
    app         = "spark-airflow-aiven"
    managed_by  = "terraform"
    environment = "prod"
  }
}

variable "env_secret_id" {
  type        = string
  description = "Secret Manager secret ID that stores the full .env payload for the app."
  default     = "spark-airflow-aiven-env"
}

variable "ca_secret_id" {
  type        = string
  description = "Secret Manager secret ID that stores the Aiven CA certificate PEM."
  default     = "spark-airflow-aiven-aiven-ca-pem"
}

variable "app_env_secret_payload" {
  type        = string
  description = "Optional initial payload for the app .env secret."
  sensitive   = true
  default     = null
}

variable "aiven_ca_certificate_pem" {
  type        = string
  description = "Optional initial payload for the Aiven CA certificate secret."
  sensitive   = true
  default     = null
}
