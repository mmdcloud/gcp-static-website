############################################
# Global static IP(s)
############################################
resource "google_compute_global_address" "ipv4" {
  count = var.create_static_ip ? 1 : 0

  project      = var.project_id
  name         = "${var.name}-ipv4"
  ip_version   = "IPV4"
  address_type = "EXTERNAL"
}

resource "google_compute_global_address" "ipv6" {
  count = var.create_static_ip && var.enable_ipv6 ? 1 : 0

  project      = var.project_id
  name         = "${var.name}-ipv6"
  ip_version   = "IPV6"
  address_type = "EXTERNAL"
}

locals {
  lb_ipv4_address = var.create_static_ip ? google_compute_global_address.ipv4[0].address : var.reserved_ip_address
}

############################################
# Per-backend health checks (only created when
# the caller doesn't pass an existing health_check_id)
############################################
resource "google_compute_health_check" "this" {
  for_each = { for k, v in var.backends : k => v if v.manage_health_check }

  project             = var.project_id
  name                = "${var.name}-${each.key}-hc"
  check_interval_sec  = each.value.health_check.check_interval_sec
  timeout_sec         = each.value.health_check.timeout_sec
  healthy_threshold   = each.value.health_check.healthy_threshold
  unhealthy_threshold = each.value.health_check.unhealthy_threshold

  http_health_check {
    port         = each.value.health_check.port
    request_path = each.value.health_check.request_path
  }
}

locals {
  health_check_ids = {
    for k, v in var.backends :
    k => coalesce(v.health_check_id, try(google_compute_health_check.this[k].id, null))
  }
}

############################################
# Cloud Armor security policy
############################################
resource "google_compute_security_policy" "this" {
  count = var.enable_cloud_armor ? 1 : 0

  project     = var.project_id
  name        = "${var.name}-armor-policy"
  description = "Cloud Armor policy for ${var.name}: WAF preconfigured rules, rate limiting, allow/deny lists."

  # Default catch-all rule (lowest priority, evaluated last)
  rule {
    action      = var.cloud_armor_default_action
    priority    = 2147483647
    description = "Default rule"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }

  # Explicit allowlist (evaluated before deny/WAF rules)
  dynamic "rule" {
    for_each = length(var.cloud_armor_allowlist_ip_ranges) > 0 ? [1] : []
    content {
      action      = "allow"
      priority    = 1000
      description = "Explicit allowlist"
      match {
        versioned_expr = "SRC_IPS_V1"
        config {
          src_ip_ranges = var.cloud_armor_allowlist_ip_ranges
        }
      }
    }
  }

  # Explicit denylist
  dynamic "rule" {
    for_each = length(var.cloud_armor_denylist_ip_ranges) > 0 ? [1] : []
    content {
      action      = "deny(403)"
      priority    = 1100
      description = "Explicit denylist"
      match {
        versioned_expr = "SRC_IPS_V1"
        config {
          src_ip_ranges = var.cloud_armor_denylist_ip_ranges
        }
      }
    }
  }

  # Preconfigured WAF rules (SQLi, XSS, LFI, RCE, etc.)
  dynamic "rule" {
    for_each = { for idx, rule_id in var.cloud_armor_preconfigured_rules : idx => rule_id }
    content {
      action      = "deny(403)"
      priority    = 1200 + tonumber(rule.key)
      description = "Preconfigured WAF rule: ${rule.value}"
      match {
        expr {
          expression = "evaluatePreconfiguredExpr('${rule.value}')"
        }
      }
    }
  }

  # Adaptive protection (L7 DDoS)
  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }

  rule {
    action      = "rate_based_ban"
    priority    = 2000
    description = "Rate limit per client IP; ban offenders that exceed 5x the threshold"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = var.cloud_armor_rate_limit_threshold_count
        interval_sec = var.cloud_armor_rate_limit_interval_sec
      }
      ban_duration_sec = var.cloud_armor_rate_limit_ban_duration_sec
      ban_threshold {
        count        = var.cloud_armor_rate_limit_threshold_count * 5
        interval_sec = var.cloud_armor_rate_limit_interval_sec
      }
    }
  }
}

############################################
# Backend services
############################################
resource "google_compute_backend_service" "this" {
  for_each = var.backends

  project     = var.project_id
  name        = "${var.name}-${each.key}-backend"
  description = each.value.description
  protocol    = each.value.protocol
  port_name   = each.value.port_name
  timeout_sec = each.value.timeout_sec

  load_balancing_scheme = "EXTERNAL_MANAGED"
  health_checks          = [local.health_check_ids[each.key]]
  security_policy        = var.enable_cloud_armor ? google_compute_security_policy.this[0].id : null

  enable_cdn = each.value.enable_cdn

  dynamic "cdn_policy" {
    for_each = each.value.enable_cdn ? [1] : []
    content {
      cache_mode        = "CACHE_ALL_STATIC"
      default_ttl       = 3600
      client_ttl        = 3600
      max_ttl           = 86400
      negative_caching  = true
      serve_while_stale = 86400
    }
  }

  dynamic "backend" {
    for_each = each.value.groups
    content {
      group           = backend.value.group
      balancing_mode  = backend.value.balancing_mode
      capacity_scaler = backend.value.capacity_scaler
      max_utilization = backend.value.balancing_mode == "UTILIZATION" ? backend.value.max_utilization : null
    }
  }

  dynamic "log_config" {
    for_each = var.enable_logging ? [1] : []
    content {
      enable      = true
      sample_rate = each.value.log_sample_rate
    }
  }
}

############################################
# URL map (path/host routing)
############################################

locals {
  default_backend_key = one([for k, v in var.backends : k if v.is_default])

  # host_rule/path_matcher entries only for non-default backends with explicit
  # host or path patterns configured.
  routed_backends = {
    for k, v in var.backends :
    k => v if !v.is_default && (length(v.host_patterns) > 0 || length(v.path_patterns) > 0)
  }
}

resource "google_compute_url_map" "this" {
  project         = var.project_id
  name            = "${var.name}-url-map"
  default_service = google_compute_backend_service.this[local.default_backend_key].id
  default_url_redirect {
    https_redirect         = false
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query             = false
  }
  dynamic "host_rule" {
    for_each = local.routed_backends
    content {
      hosts        = length(host_rule.value.host_patterns) > 0 ? host_rule.value.host_patterns : ["*"]
      path_matcher = "${host_rule.key}-matcher"
    }
  }

  dynamic "path_matcher" {
    for_each = local.routed_backends
    content {
      name            = "${path_matcher.key}-matcher"
      default_service = google_compute_backend_service.this[path_matcher.key].id

      dynamic "path_rule" {
        for_each = length(path_matcher.value.path_patterns) > 0 ? [1] : []
        content {
          paths   = path_matcher.value.path_patterns
          service = google_compute_backend_service.this[path_matcher.key].id
        }
      }
    }
  }
}

############################################
# HTTP -> HTTPS redirect (port 80)
############################################
# resource "google_compute_url_map" "http_redirect" {
#   count = var.enable_http_redirect ? 1 : 0

#   project = var.project_id
#   name    = "${var.name}-http-redirect"

#   default_url_redirect {
#     https_redirect         = false
#     redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
#     strip_query             = false
#   }
# }

resource "google_compute_target_http_proxy" "this" {
  count = var.enable_http_redirect ? 1 : 0

  project = var.project_id
  name    = "${var.name}-http-proxy"
  url_map = google_compute_url_map.this.id
}

resource "google_compute_global_forwarding_rule" "http" {
  count = var.enable_http_redirect ? 1 : 0

  project               = var.project_id
  name                  = "${var.name}-http-fr"
  target                = google_compute_target_http_proxy.this[0].id
  port_range            = "80"
  ip_address             = local.lb_ipv4_address
  load_balancing_scheme = "EXTERNAL_MANAGED"
  labels                = var.labels
}

############################################
# Managed SSL certificate / SSL policy
############################################

# resource "google_compute_managed_ssl_certificate" "this" {
#   count = var.managed_ssl_certificate ? 1 : 0

#   project = var.project_id
#   name    = "${var.name}-cert"

#   managed {
#     domains = var.domains
#   }

#   lifecycle {
#     create_before_destroy = true
#   }
# }

# resource "google_compute_ssl_policy" "this" {
#   project         = var.project_id
#   name            = "${var.name}-ssl-policy"
#   profile         = var.ssl_policy_profile
#   min_tls_version = var.ssl_policy_min_tls_version
# }

# ############################################
# # HTTPS proxy + forwarding rule (port 443)
# ############################################

# resource "google_compute_target_https_proxy" "this" {
#   project = var.project_id
#   name    = "${var.name}-https-proxy"
#   url_map = google_compute_url_map.this.id

#   ssl_certificates = var.managed_ssl_certificate ? [google_compute_managed_ssl_certificate.this[0].id] : var.ssl_certificate_ids
#   ssl_policy       = google_compute_ssl_policy.this.id
# }

# resource "google_compute_global_forwarding_rule" "https" {
#   project               = var.project_id
#   name                  = "${var.name}-https-fr"
#   target                = google_compute_target_https_proxy.this.id
#   port_range            = "443"
#   ip_address             = local.lb_ipv4_address
#   load_balancing_scheme = "EXTERNAL_MANAGED"
#   labels                = var.labels
# }

# resource "google_compute_global_forwarding_rule" "https_ipv6" {
#   count = var.enable_ipv6 ? 1 : 0

#   project               = var.project_id
#   name                  = "${var.name}-https-fr-ipv6"
#   target                = google_compute_target_https_proxy.this.id
#   port_range            = "443"
#   ip_address             = var.create_static_ip ? google_compute_global_address.ipv6[0].address : null
#   load_balancing_scheme = "EXTERNAL_MANAGED"
#   labels                = var.labels
# }