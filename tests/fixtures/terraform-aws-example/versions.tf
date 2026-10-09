# A minimal module that follows the module rules. CI runs the module-checks action against it,
# tests included, so a release can't ship checks that reject a conforming module.
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68"
    }
  }
}
