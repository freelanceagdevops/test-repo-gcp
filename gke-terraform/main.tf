terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

# Create custom VPC
resource "google_compute_network" "custom_network" {
  name                    = "custom-vpc"
  auto_create_subnetworks = false
}

# Create custom Subnet
resource "google_compute_subnetwork" "custom_subnet" {
  name          = "custom-subnetwork"
  ip_cidr_range = "10.10.0.0/16"
  region        = var.region
  network       = google_compute_network.custom_network.id
}

# Firewall-1: Internal communication
resource "google_compute_firewall" "allow_internal" {
  name    = "internal-firewall"
  network = google_compute_network.custom_network.id

  allow {
    protocol = "all"
  }

  source_ranges = ["10.10.0.0/16"]
}

# Firewall-2: External SSH, ICMP, RDP
resource "google_compute_firewall" "allow_external" {
  name    = "external-firewall"
  network = google_compute_network.custom_network.id

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22", "3389"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# Firewall-3: GKE communication
resource "google_compute_firewall" "allow_gke" {
  name    = "gke-firewall"
  network = google_compute_network.custom_network.id

  allow {
    protocol = "tcp"
    ports    = ["443", "10250", "15017"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# Docker Artifact Registry
resource "google_artifact_registry_repository" "docker_repo" {
  location      = var.region
  repository_id = "docker-repo"
  description   = "Docker repository"
  format        = "DOCKER"
}

# GKE Cluster
resource "google_container_cluster" "primary" {
  project                  = var.project
  name                     = "terraform-gke-cluster"
  location                 = var.region
  network                  = google_compute_network.custom_network.id
  subnetwork               = google_compute_subnetwork.custom_subnet.id
  deletion_protection      = false
  remove_default_node_pool = true
  initial_node_count       = 1
}

# GKE Node Pool
resource "google_container_node_pool" "primary_preemptible_nodes" {
  name       = "my-node-pool"
  cluster    = google_container_cluster.primary.name
  location   = google_container_cluster.primary.location
  node_count = 1

  node_config {
    machine_type = "e2-medium"
    disk_size_gb = 15
    disk_type    = "pd-standard"
    image_type   = "UBUNTU_CONTAINERD"
  }
}

