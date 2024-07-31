terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.38.0"
    }
  }
}

provider "google" {
  project = "master-sector-430909-i0"
  region  = "us-central1"
}
