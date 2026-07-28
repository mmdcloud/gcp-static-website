variable "contents" {
  type = list(object({
    name        = string
    source_path = string
    content     = string
  }))
}
variable "location" {}
variable "storage_class" {
  type    = string
  default = null
}
variable "public_access_prevention" {
  type    = string
  default = null
}
variable "name" {}
variable "versioning" {
  default = false
}
variable "lifecycle_rules" {
  type = list(object({
    action = object({
      type          = string
      storage_class = optional(string)
    })
    condition = object({
      age = optional(number)
      num_newer_versions = optional(number)
    })
  }))
  default = []
}
variable "force_destroy" {}
variable "website" {
  type = object({
    main_page_suffix = optional(string)
    not_found_page   = optional(string)
  })
  default = {}
}
variable "notifications" {
  type = list(object({
    topic_id = string
  }))
  default = []
}
variable "uniform_bucket_level_access" {
  type    = bool
  default = true
}
# variable "contents" {
#   type = list(object({
#     name        = string
#     source_path = string
#     content     = string
#   }))
# }
variable "cors" {
  type = list(object({
    max_age_seconds = string
    method          = list(string)
    origin          = list(string)
    response_header = list(string)
  }))
}
