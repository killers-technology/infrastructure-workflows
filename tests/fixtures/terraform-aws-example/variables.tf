variable "name" {
  description = "Parameter name, without the leading slash."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9/_-]+$", var.name))
    error_message = "name may only contain lowercase letters, digits, slashes, underscores and hyphens."
  }
}

variable "value" {
  description = "Parameter value."
  type        = string
}
