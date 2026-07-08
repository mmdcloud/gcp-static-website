# terraform {
#   required_providers {
#     google = {
#       source  = "hashicorp/google"
#       version = "~> 6.0"
#     }
#   }
# }

# provider "google" {
#   project = "encoded-alpha-457108-e8"
#   region  = "us-central1"
# }
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # ---------------------------------------------------------------------------
  # Remote state backend — replace bucket/prefix with your own values.
  # Run `terraform init` after configuring this for the first time.
  # ---------------------------------------------------------------------------
  # backend "gcs" {
  #   bucket = "your-tfstate-bucket"   # <-- change me
  #   prefix = "website/prod"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
