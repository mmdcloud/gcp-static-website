# Bucket to store website
resource "google_storage_bucket" "append_website" {
  name          = "append_website"
  storage_class = "STANDARD"
  autoclass {
    enabled = false
  }
  enable_object_retention     = false
  force_destroy               = true
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  requester_pays              = false
  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
  location = var.region
}

# Upload website files to cloud storage bucket 
resource "google_storage_bucket_object" "append_obj" {
  for_each = fileset("../Append/", "**")
  name     = each.value
  source   = each.key
  # source   = "/images/nature/garden-tiger-moth.jpg"
  bucket = google_storage_bucket.append_website.name
}

# Make new objects public
resource "google_storage_default_object_access_control" "append_access_control" {
  bucket = google_storage_bucket.append_website.name
  role   = "READER"
  entity = "allUsers"
}

# Reserve an external IP
resource "google_compute_global_address" "append_compute_global_address" {
  name         = "append_compute_global_address"
  address_type = "EXTERNAL"
}

# Get the managed DNS zone
data "google_dns_managed_zone" "append_dns_managed_zone" {
  name = "append_dns_managed_zone"
}

# Add the IP to the DNS
resource "google_dns_record_set" "append_dns_record_set" {
  name         = "website.${var.domain}"
  type         = "A"
  ttl          = 300
  managed_zone = var.domain
  rrdatas      = [google_compute_global_address.website.address]
}

# Add the bucket as a CDN backend
resource "google_compute_backend_bucket" "append_website_cdn" {
  name        = "append_website_cdn"
  description = "Contains files needed by the website"
  bucket_name = google_storage_bucket.append_website.name
  enable_cdn  = true
}

# Create HTTPS certificate
resource "google_compute_managed_ssl_certificate" "append_cert" {
  name = "append_cert"
  managed {
    domains = [google_dns_record_set.append_dns_record_set.name]
  }
}

# GCP URL MAP
resource "google_compute_url_map" "append_compute_url_map" {
  name            = "append_compute_url_map"
  default_service = google_compute_backend_bucket.append_website_cdn.self_link
}

# GCP target proxy
resource "google_compute_target_https_proxy" "append_target_proxy" {
  provider         = google
  name             = "append_target_proxy"
  url_map          = google_compute_url_map.append_compute_url_map.self_link
  ssl_certificates = [google_compute_managed_ssl_certificate.append_cert.self_link]
}

# GCP forwarding rule
resource "google_compute_global_forwarding_rule" "append_global_forwarding_rule" {
  name                  = "append_global_forwarding_rule"
  load_balancing_scheme = "EXTERNAL"
  ip_address            = google_compute_global_address.append_compute_global_address.address
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.append_target_proxy.self_link
}
