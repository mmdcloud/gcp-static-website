locals {
  bucket_name = "${var.bucket_name_prefix}-${var.environment}-website"

  # Build a map of { relative_path => mime_type } for every file in src_dir.
  # The external data source calls a small Python helper to resolve MIME types.
  src_files = fileset(var.src_dir, "**")
}

data "google_project" "current" {}

# -------------------------------------------------------------------------------
# MIME type resolution (one call per source file)
# -------------------------------------------------------------------------------
data "external" "mime_type" {
  for_each = local.src_files
  program  = ["python3", "${path.module}/scripts/get_mime_type.py", "${var.src_dir}/${each.value}"]
}

# -------------------------------------------------------------------------------
# GCS bucket 
# -------------------------------------------------------------------------------
module "website_bucket" {
  source        = "./modules/gcs"
  project_id    = var.project_id
  location      = var.region
  name          = local.bucket_name
  storage_class = "STANDARD"
  cors = [
    {
      origin          = ["*"]
      max_age_seconds = 3600
      method          = ["GET", "POST", "PUT", "DELETE"]
      response_header = ["*"]
    }
  ]
  versioning = true
  website = {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
  lifecycle_rules = [
    {
      condition = {
        num_newer_versions = 1
      }
      action = {
        type = "Delete"
      }
    }
  ]
  public_access_prevention    = "enforced"
  contents                    = []
  notifications               = []
  force_destroy               = true
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_object" "website_files" {
  for_each     = local.src_files
  name         = each.value
  source       = "${var.src_dir}/${each.value}"
  content_type = data.external.mime_type[each.value].result["mime_type"]
  bucket       = module.website_bucket.bucket_name
}

# -------------------------------------------------------------------------------
# Grant the Cloud Storage service account permission to serve objects via CDN.
# This replaces the insecure "allUsers → objectAdmin" binding.
# -------------------------------------------------------------------------------
data "google_storage_project_service_account" "gcs_account" {}

resource "google_storage_bucket_iam_member" "lb_object_viewer" {
  bucket = module.website_bucket.bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:service-${data.google_project.current.number}@https-lb.iam.gserviceaccount.com"
}

resource "google_storage_bucket_iam_member" "cdn_object_viewer" {
  bucket = module.website_bucket.bucket_name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"
}

# -------------------------------------------------------------------------------
# Load Balanacer Configuration (with CDN)
# -------------------------------------------------------------------------------
module "lb" {
  source     = "./modules/load-balancer"
  project_id = var.project_id
  name       = "lb"

  backend_buckets = {
    website = {
      is_default  = true
      enable_cdn  = true
      bucket_name = module.website_bucket.bucket_name
    }
  }

  enable_ssl              = false
  enable_http             = true
  managed_ssl_certificate = false
  enable_cloud_armor      = false
  depends_on              = [module.website_bucket]
}

# --------------------------------------------------------------------------
# DNS Configuration
# --------------------------------------------------------------------------
module "dns" {
  source     = "./modules/cloud-dns"
  name       = "mohitd.xyz"
  domain     = "mohitd.xyz."
  project_id = var.project_id
  type       = "public"

  recordsets = [
    {
      name    = "website.mohitd.xyz"
      type    = "A"
      ttl     = 500
      records = [module.lb.lb_ip_address]
    }
  ]
}