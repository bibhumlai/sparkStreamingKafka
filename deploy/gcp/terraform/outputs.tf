output "vm_name" {
  description = "Compute Engine VM name."
  value       = google_compute_instance.app.name
}

output "vm_external_ip" {
  description = "External IP address assigned to the VM."
  value       = google_compute_address.vm.address
}

output "airflow_url" {
  description = "Airflow UI URL. If airflow_base_url was omitted, this uses the reserved external IP."
  value       = var.airflow_base_url != null ? var.airflow_base_url : "http://${google_compute_address.vm.address}:8088"
}

output "ssh_command" {
  description = "Convenient SSH command for direct access."
  value       = "ssh ${var.ssh_username}@${google_compute_address.vm.address}"
}

output "service_account_email" {
  description = "Dedicated service account attached to the VM."
  value       = google_service_account.vm.email
}

output "secret_names" {
  description = "Secret Manager secret IDs expected by the startup script."
  value = {
    app_env  = google_secret_manager_secret.app_env.secret_id
    aiven_ca = google_secret_manager_secret.aiven_ca.secret_id
  }
}
