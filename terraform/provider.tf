terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.12.0"
    }
  }
}

provider "google" {
  project = "orbital-bee-455915-h5"
  region  = "us-central1"
}
