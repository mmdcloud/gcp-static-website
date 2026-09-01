variable "project_id" {
  description = "GCP project ID where all resources will be created."
  type        = string
  # No default — must be supplied via tfvars or environment so it is explicit per environment.
}

variable "region" {
  description = "GCP region for regional resources (e.g. Cloud Storage bucket location)."
  type        = string
  default     = "US" # multi-region for better availability; change to a single region if needed
}

variable "environment" {
  description = "Deployment environment label (e.g. dev, staging, prod)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix for the GCS bucket name. Full name becomes '<prefix>-<environment>-website'."
  type        = string
  default     = "append"
}

variable "src_dir" {
  description = "Relative path to the website source directory (from the Terraform root module)."
  type        = string
  default     = "../src"
}