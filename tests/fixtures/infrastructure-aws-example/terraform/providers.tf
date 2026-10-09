provider "aws" {
  region              = var.region       # set by the definition, never hardcoded
  allowed_account_ids = [var.account_id] # refuses to run against the wrong account

  default_tags {
    tags = {
      Project     = "example"
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "killers-technology/infrastructure-aws-example"
    }
  }
}
