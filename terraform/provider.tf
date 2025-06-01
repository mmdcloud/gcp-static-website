terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.12.0"
    }
  }
}

provider "google" {
  project = "encoded-alpha-457108-e8"
  region  = "us-central1"
}
