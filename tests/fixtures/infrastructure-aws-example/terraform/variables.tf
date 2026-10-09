variable "region" {
  description = "The one region this run deploys to."
  type        = string

  validation {
    condition     = contains(["us-east-1", "us-west-2"], var.region)
    error_message = "Only us-east-1 and us-west-2 are allowed."
  }
}

variable "account_id" {
  description = "The account this definition deploys to."
  type        = string
}

variable "environment" {
  description = "The environment of this definition."
  type        = string

  validation {
    condition     = contains(["non-prod", "prod"], var.environment)
    error_message = "environment must be non-prod or prod."
  }
}
