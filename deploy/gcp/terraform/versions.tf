terraform {
  required_version = ">= 1.7.0"

  backend "gcs" {
    bucket = "terraform-state-bibhu"
    prefix = "spark"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.20"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}
