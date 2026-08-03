############################################
# Core / naming
############################################

variable "project_id" {
  description = "GCP project ID to deploy resources into."
  type        = string
}

variable "name" {
  description = "Base name used to derive names for all LB resources (IP, backend service, URL map, proxies, forwarding rules, cert, security policy)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a valid RFC1035 label: lowercase letters, numbers, hyphens; must start with a letter."
  }
}

variable "labels" {
  description = "Labels applied to supported resources (backend service, forwarding rules)."
  type        = map(string)
  default     = {}
}

############################################
# Frontend: IP, domains, TLS
############################################

variable "create_static_ip" {
  description = "Whether to reserve a new global static external IP. Set false and supply reserved_ip_address to reuse an existing one."
  type        = bool
  default     = true
}

variable "reserved_ip_address" {
  description = "Existing reserved global IP address to use when create_static_ip = false."
  type        = string
  default     = null
}

variable "domains" {
  description = "Domain names for the Google-managed SSL certificate (e.g. ['app.example.com']). Required when managed_ssl_certificate = true. Each domain must already have DNS pointed at the LB's IP for provisioning to succeed."
  type        = list(string)
  default     = []
}

variable "managed_ssl_certificate" {
  description = "Whether to provision a Google-managed SSL certificate from var.domains. Set false to supply your own certificate(s) via ssl_certificate_ids."
  type        = bool
  default     = true
}

variable "ssl_certificate_ids" {
  description = "Self links of pre-existing SSL certificates to attach to the HTTPS proxy, used when managed_ssl_certificate = false."
  type        = list(string)
  default     = []
}

variable "ssl_policy_min_tls_version" {
  description = "Minimum TLS version enforced by the LB's SSL policy."
  type        = string
  default     = "TLS_1_2"

  validation {
    condition     = contains(["TLS_1_0", "TLS_1_1", "TLS_1_2"], var.ssl_policy_min_tls_version)
    error_message = "ssl_policy_min_tls_version must be one of: TLS_1_0, TLS_1_1, TLS_1_2."
  }
}

variable "ssl_policy_profile" {
  description = "SSL policy profile controlling allowed cipher suites."
  type        = string
  default     = "MODERN"

  validation {
    condition     = contains(["COMPATIBLE", "MODERN", "RESTRICTED", "CUSTOM"], var.ssl_policy_profile)
    error_message = "ssl_policy_profile must be one of: COMPATIBLE, MODERN, RESTRICTED, CUSTOM."
  }
}

variable "enable_http_redirect" {
  description = "Whether to provision a port-80 listener that permanently redirects all HTTP traffic to HTTPS. Recommended for production."
  type        = bool
  default     = true
}

variable "enable_ipv6" {
  description = "Whether to also reserve/serve an IPv6 global address alongside IPv4."
  type        = bool
  default     = false
}

############################################
# Backend(s)
############################################

variable "backends" {
  description = <<-EOT
    Map of backend services to create, keyed by a short logical name (used in resource naming).
    Each backend maps to one google_compute_backend_service, fed by one or more instance groups
    (typically MIG self_links, e.g. from the instance-group module's instance_group_self_link output).
  EOT
  type = map(object({
    description = optional(string, "")
    protocol    = optional(string, "HTTP") # HTTP, HTTPS, HTTP2
    port_name   = optional(string, "http")
    timeout_sec = optional(number, 30)
    enable_cdn  = optional(bool, false)

    # Existing health check ID/self_link to reuse (e.g. from the instance-group module).
    # If null, a new HTTP health check is created for this backend.
    health_check_id     = optional(string, null)
    manage_health_check = optional(bool, true)
    health_check = optional(object({
      port                = optional(number, 80)
      request_path        = optional(string, "/")
      check_interval_sec  = optional(number, 10)
      timeout_sec         = optional(number, 5)
      healthy_threshold   = optional(number, 2)
      unhealthy_threshold = optional(number, 3)
    }), {})

    groups = list(object({
      group           = string # instance group / NEG self_link
      balancing_mode  = optional(string, "UTILIZATION")
      capacity_scaler = optional(number, 1.0)
      max_utilization = optional(number, 0.8)
    }))

    log_sample_rate = optional(number, 1.0)

    # Path patterns (URL map) that route to this backend. The backend listed with
    # is_default = true (exactly one required) handles all otherwise-unmatched traffic.
    is_default    = optional(bool, false)
    host_patterns = optional(list(string), []) # e.g. ["app.example.com"]
    path_patterns = optional(list(string), []) # e.g. ["/api/*"]
  }))

  validation {
    condition     = length([for k, v in var.backends : k if v.is_default]) == 1
    error_message = "Exactly one entry in var.backends must have is_default = true."
  }
}

############################################
# Cloud Armor (WAF / rate limiting)
############################################

variable "enable_cloud_armor" {
  description = "Whether to create and attach a Cloud Armor security policy to all backend services."
  type        = bool
  default     = true
}

variable "cloud_armor_default_action" {
  description = "Default action for the Cloud Armor policy when no rule matches: 'allow' or 'deny(403)' etc."
  type        = string
  default     = "allow"
}

variable "cloud_armor_rate_limit_threshold_count" {
  description = "Number of requests allowed per client IP within the rate-limit interval before throttling/blocking."
  type        = number
  default     = 100
}

variable "cloud_armor_rate_limit_interval_sec" {
  description = "Rate-limit sliding window, in seconds. Also used as the ban-threshold interval, which GCP restricts to one of: 60, 120, 180, 240, 300, 600, 900, 1200, 1800, 2700, 3600."
  type        = number
  default     = 60

  validation {
    condition     = contains([60, 120, 180, 240, 300, 600, 900, 1200, 1800, 2700, 3600], var.cloud_armor_rate_limit_interval_sec)
    error_message = "cloud_armor_rate_limit_interval_sec must be one of: 60, 120, 180, 240, 300, 600, 900, 1200, 1800, 2700, 3600 (required for the ban_threshold interval)."
  }
}

variable "cloud_armor_rate_limit_ban_duration_sec" {
  description = "How long an offending client IP is banned after exceeding the rate limit."
  type        = number
  default     = 300
}

variable "cloud_armor_preconfigured_rules" {
  description = "Preconfigured WAF rule sets (Cloud Armor managed rules) to enable, e.g. ['sqli-v33-stable', 'xss-v33-stable', 'lfi-v33-stable']. Empty list disables preconfigured WAF rules (rate limiting still applies if enabled)."
  type        = list(string)
  default     = ["sqli-v33-stable", "xss-v33-stable", "lfi-v33-stable", "rce-v33-stable"]
}

variable "cloud_armor_allowlist_ip_ranges" {
  description = "Optional list of CIDR ranges always allowed, evaluated before WAF/rate-limit rules (e.g. office IPs, health-check ranges you want exempted)."
  type        = list(string)
  default     = []
}

variable "cloud_armor_denylist_ip_ranges" {
  description = "Optional list of CIDR ranges always denied."
  type        = list(string)
  default     = []
}

############################################
# Logging
############################################

variable "enable_logging" {
  description = "Whether to enable backend service access logging (exported to Cloud Logging)."
  type        = bool
  default     = true
}