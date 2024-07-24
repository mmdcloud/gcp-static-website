terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.38.0"
    }
  }
}

provider "google" {
  project = "custom-ground-424107-q4"
  region  = "us-central1"
}
