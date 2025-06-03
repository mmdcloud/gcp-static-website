# Getting MIME type for each of the files
data "external" "mime_type" {
  for_each = fileset("../Append/", "**")
  program  = ["python3", "${path.module}/scripts/get_mime_type.py", "../../Append/${each.value}"]
}

# Bucket to store website
resource "google_storage_bucket" "append_website" {
  name          = "append_website"
  storage_class = "STANDARD"
  autoclass {
    enabled = false
  }
  enable_object_retention  = false
  force_destroy            = true
  public_access_prevention = "inherited"
  requester_pays           = false
  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
  location = var.region
}

# Upload website files to cloud storage bucket 
resource "google_storage_bucket_object" "append_obj" {
  for_each     = fileset("../Append/", "**")
  name         = each.value
  source       = "../Append/${each.value}"
  content_type = data.external.mime_type[each.value].result["mime_type"]
  bucket       = google_storage_bucket.append_website.name
}

# Cloud storage IAM binding
resource "google_storage_bucket_iam_binding" "storage_iam_binding" {
  bucket = google_storage_bucket.append_website.name
  role   = "roles/storage.objectAdmin"

  members = [
    "allUsers"
  ]
}

# Add the bucket as a CDN backend
resource "google_compute_backend_bucket" "append_website_cdn" {
  name        = "append-website-cdn"
  description = "Content delivery network for append website bucket"
  bucket_name = google_storage_bucket.append_website.name
  enable_cdn  = true
}

# Reserve an external IP
resource "google_compute_global_address" "append_compute_global_address" {
  name         = "append-compute-global-address"
  address_type = "EXTERNAL"
}

# GCP URL MAP
resource "google_compute_url_map" "append_compute_url_map" {
  name            = "append-compute-url-map"
  default_service = google_compute_backend_bucket.append_website_cdn.self_link
  host_rule {
    hosts        = ["*"]
    path_matcher = "allpaths"
  }
  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_bucket.append_website_cdn.self_link
  }
}

# If DNS records are to be attached then use 'google_compute_target_http_proxy'

# GCP target proxy
resource "google_compute_target_http_proxy" "append_target_proxy" {
  provider = google
  name     = "append-target-proxy"
  url_map  = google_compute_url_map.append_compute_url_map.self_link
}

# GCP forwarding rule
resource "google_compute_global_forwarding_rule" "append_global_forwarding_rule" {
  name                  = "append-global-forwarding-rule"
  load_balancing_scheme = "EXTERNAL"
  ip_address            = google_compute_global_address.append_compute_global_address.address
  port_range            = "80"
  target                = google_compute_target_http_proxy.append_target_proxy.self_link
}
