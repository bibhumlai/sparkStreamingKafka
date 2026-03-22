locals {
  airflow_source_ranges = length(var.airflow_ui_source_ranges) > 0 ? var.airflow_ui_source_ranges : var.admin_source_ranges
  airflow_source_ranges_ipv4 = [
    for cidr in local.airflow_source_ranges : cidr
    if can(regex("\\.", cidr))
  ]
  airflow_source_ranges_ipv6 = [
    for cidr in local.airflow_source_ranges : cidr
    if can(regex(":", cidr))
  ]
}

data "google_compute_network" "selected" {
  name = var.network_name
}

data "google_compute_subnetwork" "selected" {
  count  = var.subnetwork_name == null ? 0 : 1
  name   = var.subnetwork_name
  region = var.gcp_region
}

data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

resource "google_service_account" "vm" {
  account_id   = var.service_account_name
  display_name = "Spark Airflow Aiven VM"
}

resource "google_project_iam_member" "vm_secret_accessor" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.vm.email}"
}

resource "google_project_iam_member" "vm_logging" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.vm.email}"
}

resource "google_project_iam_member" "vm_monitoring" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.vm.email}"
}

resource "google_compute_address" "vm" {
  name   = "${var.vm_name}-ip"
  region = var.gcp_region
}

resource "google_secret_manager_secret" "app_env" {
  secret_id = var.env_secret_id

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret" "aiven_ca" {
  secret_id = var.ca_secret_id

  replication {
    auto {}
  }

  labels = var.labels
}

resource "google_secret_manager_secret_version" "app_env" {
  count       = var.app_env_secret_payload == null ? 0 : 1
  secret      = google_secret_manager_secret.app_env.id
  secret_data = var.app_env_secret_payload
}

resource "google_secret_manager_secret_version" "aiven_ca" {
  count       = var.aiven_ca_certificate_pem == null ? 0 : 1
  secret      = google_secret_manager_secret.aiven_ca.id
  secret_data = var.aiven_ca_certificate_pem
}

resource "google_compute_firewall" "ssh" {
  name    = "${var.vm_name}-allow-ssh"
  network = data.google_compute_network.selected.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.admin_source_ranges
  target_tags   = [var.vm_name]
}

resource "google_compute_firewall" "app_ipv4" {
  count   = length(local.airflow_source_ranges_ipv4) > 0 ? 1 : 0
  name    = "${var.vm_name}-allow-app-ipv4"
  network = data.google_compute_network.selected.name

  allow {
    protocol = "tcp"
    ports    = var.open_tcp_ports
  }

  source_ranges = local.airflow_source_ranges_ipv4
  target_tags   = [var.vm_name]
}

resource "google_compute_firewall" "app_ipv6" {
  count   = length(local.airflow_source_ranges_ipv6) > 0 ? 1 : 0
  name    = "${var.vm_name}-allow-app-ipv6"
  network = data.google_compute_network.selected.name

  allow {
    protocol = "tcp"
    ports    = var.open_tcp_ports
  }

  source_ranges = local.airflow_source_ranges_ipv6
  target_tags   = [var.vm_name]
}

resource "google_compute_instance" "app" {
  name         = var.vm_name
  zone         = var.gcp_zone
  machine_type = var.machine_type
  tags         = [var.vm_name]
  labels       = var.labels

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = var.boot_disk_size_gb
      type  = var.boot_disk_type
    }
  }

  network_interface {
    network    = data.google_compute_network.selected.id
    subnetwork = var.subnetwork_name == null ? null : data.google_compute_subnetwork.selected[0].id

    access_config {
      nat_ip = google_compute_address.vm.address
    }
  }

  metadata = {
    ssh-keys = "${var.ssh_username}:${var.ssh_public_key}"
  }

  metadata_startup_script = templatefile("${path.module}/templates/startup.sh.tpl", {
    app_directory    = var.app_directory
    airflow_base_url = var.airflow_base_url
    ca_secret_id     = google_secret_manager_secret.aiven_ca.secret_id
    env_secret_id    = google_secret_manager_secret.app_env.secret_id
    gcp_project_id   = var.gcp_project_id
    repo_branch      = var.repo_branch
    repo_url         = var.repo_url
    ssh_username     = var.ssh_username
  })

  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"]
  }

  allow_stopping_for_update = true

  depends_on = [
    google_project_iam_member.vm_secret_accessor,
    google_project_iam_member.vm_logging,
    google_project_iam_member.vm_monitoring,
  ]
}
