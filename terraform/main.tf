# Bucket to store website
resource "google_storage_bucket" "append_website" {
  name          = "append_website"
  storage_class = "STANDARD"
  autoclass {
    enabled = false
  }
  enable_object_retention     = false
  force_destroy               = true
  uniform_bucket_level_access = false
  public_access_prevention    = "inherited"
  requester_pays              = false
  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
  location = var.region
}

# Registering a domain
resource "google_dns_managed_zone" "domain" {
  name       = "domain"
  dns_name   = "${var.domain}."
  visibility = "public"
  cloud_logging_config {
    enable_logging = false
  }
  dnssec_config {
    state = "off"
  }
  description = "append-zone"
}

# Upload website files to cloud storage bucket 
resource "google_storage_bucket_object" "append_obj" {
  for_each = fileset("../Append/", "**")
  name     = each.value
  source   = "../Append/${each.value}"
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
resource "google_compute_global_address" "appendcomputeglobaladdress" {
  name         = "appendcomputeglobaladdress"
  address_type = "EXTERNAL"
}

# Add the IP to the DNS
resource "google_dns_record_set" "append_dns_record_set" {
  name         = "website.${var.domain}."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.domain.name
  rrdatas      = [google_compute_global_address.appendcomputeglobaladdress.address]
}

# Add the bucket as a CDN backend
resource "google_compute_backend_bucket" "append_website_cdn" {
  name        = "appendwebsitecdn"
  description = "Contains files needed by the website"
  bucket_name = google_storage_bucket.append_website.name
  enable_cdn  = true
}

# Create HTTPS certificate
resource "google_compute_managed_ssl_certificate" "appendcert" {
  name = "appendcert"
  managed {
    domains = [google_dns_record_set.append_dns_record_set.name]
  }
}

# GCP URL MAP
resource "google_compute_url_map" "appendcomputeurlmap" {
  name            = "appendcomputeurlmap"
  default_service = google_compute_backend_bucket.append_website_cdn.self_link
}

# GCP target proxy
resource "google_compute_target_https_proxy" "appendtargetproxy" {
  provider         = google
  name             = "appendtargetproxy"
  url_map          = google_compute_url_map.appendcomputeurlmap.self_link
  ssl_certificates = [google_compute_managed_ssl_certificate.appendcert.self_link]
}

# GCP forwarding rule
resource "google_compute_global_forwarding_rule" "appendglobalforwardingrule" {
  name                  = "appendglobalforwardingrule"
  load_balancing_scheme = "EXTERNAL"
  ip_address            = google_compute_global_address.appendcomputeglobaladdress.address
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.appendtargetproxy.self_link
}
