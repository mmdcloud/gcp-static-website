output "website_ip" {
  description = "Static external IP address of the load balancer. Point your DNS A record here."
  value       = google_compute_global_address.website_ip.address
}

# output "website_url" {
#   description = "Public HTTPS URL of the website."
#   value       = "https://${var.domain}"
# }

output "bucket_name" {
  description = "Name of the GCS bucket hosting the website files."
  value       = google_storage_bucket.website.name
}

output "cdn_backend_name" {
  description = "Name of the CDN backend bucket resource."
  value       = google_compute_backend_bucket.website_cdn.name
}

# output "ssl_certificate_name" {
#   description = "Name of the managed SSL certificate. Check its status in the GCP console after apply."
#   value       = google_compute_managed_ssl_certificate.website_cert.name
# }