locals {
  bucket_name = "${var.bucket_name_prefix}-${var.environment}-website"

  # Build a map of { relative_path => mime_type } for every file in src_dir.
  # The external data source calls a small Python helper to resolve MIME types.
  src_files = fileset(var.src_dir, "**")
}

# -------------------------------------------------------------------------------
# MIME type resolution (one call per source file)
# -------------------------------------------------------------------------------
data "external" "mime_type" {
  for_each = local.src_files
  program  = ["python3", "${path.module}/scripts/get_mime_type.py", "${var.src_dir}/${each.value}"]
}

# -------------------------------------------------------------------------------
# GCS bucket — website hosting, no public access at the bucket level.
# Objects are served through the Load Balancer / CDN instead of directly,
# which keeps "public_access_prevention = enforced" and avoids granting
# objectAdmin to allUsers (a common misconfiguration).
# -------------------------------------------------------------------------------
resource "google_storage_bucket" "website" {
  name          = local.bucket_name
  location      = var.region
  storage_class = "STANDARD"
  force_destroy = true # (var.environment != "prod") protect prod bucket from accidental destroy
# 
  uniform_bucket_level_access = true       # required when prevention = enforced
  public_access_prevention    = "enforced" # ✅ blocks direct public object access

  versioning {
    enabled = true # allows rollback of accidental overwrites
  }

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }

  lifecycle_rule {
    action { type = "Delete" }
    condition {
      num_newer_versions = 3 # keep only last 3 versions to control storage costs
    }
  }

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# -------------------------------------------------------------------------------
# Grant the Cloud Storage service account permission to serve objects via CDN.
# This replaces the insecure "allUsers → objectAdmin" binding.
# -------------------------------------------------------------------------------
data "google_storage_project_service_account" "gcs_account" {}

resource "google_storage_bucket_iam_member" "cdn_object_viewer" {
  bucket = google_storage_bucket.website.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"
}

# -------------------------------------------------------------------------------
# Upload website files
# -------------------------------------------------------------------------------
resource "google_storage_bucket_object" "website_files" {
  for_each     = local.src_files
  name         = each.value
  source       = "${var.src_dir}/${each.value}"
  content_type = data.external.mime_type[each.value].result["mime_type"]
  bucket       = google_storage_bucket.website.name

  # Cache-busting: object is replaced when its content changes.
  # Terraform detects this via the md5hash attribute automatically.
}

# -------------------------------------------------------------------------------
# CDN backend bucket
# -------------------------------------------------------------------------------
resource "google_compute_backend_bucket" "website_cdn" {
  name        = "${local.bucket_name}-cdn"
  description = "CDN backend for the ${var.environment} website bucket"
  bucket_name = google_storage_bucket.website.name
  enable_cdn  = true

  cdn_policy {
    cache_mode        = "CACHE_ALL_STATIC"
    default_ttl       = 3600
    max_ttl           = 86400
    client_ttl        = 3600
    negative_caching  = true
    serve_while_stale = 86400 # serve stale content while revalidating (improves resilience)
  }
}

# -------------------------------------------------------------------------------
# Static external IP
# -------------------------------------------------------------------------------
resource "google_compute_global_address" "website_ip" {
  name         = "${local.bucket_name}-ip"
  address_type = "EXTERNAL"
  description  = "Static IP for the ${var.environment} website load balancer"
}

# -------------------------------------------------------------------------------
# Managed SSL certificate (replaces plain HTTP proxy)
# -------------------------------------------------------------------------------
resource "google_compute_managed_ssl_certificate" "website_cert" {
  name = "${local.bucket_name}-cert"

  managed {
    domains = [var.domain]
  }
}

# -------------------------------------------------------------------------------
# URL map — HTTP → HTTPS redirect
# -------------------------------------------------------------------------------
resource "google_compute_url_map" "http_redirect" {
  name = "${local.bucket_name}-http-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# -------------------------------------------------------------------------------
# URL map — HTTPS traffic to CDN backend
# -------------------------------------------------------------------------------
resource "google_compute_url_map" "website" {
  name            = "${local.bucket_name}-url-map"
  default_service = google_compute_backend_bucket.website_cdn.self_link

  host_rule {
    hosts        = [var.domain]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_bucket.website_cdn.self_link
  }
}

# -------------------------------------------------------------------------------
# HTTP proxy — only used for redirect to HTTPS
# -------------------------------------------------------------------------------
resource "google_compute_target_http_proxy" "http_redirect" {
  name    = "${local.bucket_name}-http-proxy"
  url_map = google_compute_url_map.http_redirect.self_link
}

# -------------------------------------------------------------------------------
# HTTPS proxy — serves real traffic
# -------------------------------------------------------------------------------
resource "google_compute_target_https_proxy" "website" {
  name             = "${local.bucket_name}-https-proxy"
  url_map          = google_compute_url_map.website.self_link
  ssl_certificates = [google_compute_managed_ssl_certificate.website_cert.self_link]
}

# -------------------------------------------------------------------------------
# Forwarding rules
# -------------------------------------------------------------------------------
resource "google_compute_global_forwarding_rule" "http" {
  name                  = "${local.bucket_name}-http-rule"
  load_balancing_scheme = "EXTERNAL"
  ip_address            = google_compute_global_address.website_ip.address
  port_range            = "80"
  target                = google_compute_target_http_proxy.http_redirect.self_link

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "google_compute_global_forwarding_rule" "https" {
  name                  = "${local.bucket_name}-https-rule"
  load_balancing_scheme = "EXTERNAL"
  ip_address            = google_compute_global_address.website_ip.address
  port_range            = "443"
  target                = google_compute_target_https_proxy.website.self_link

  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
}