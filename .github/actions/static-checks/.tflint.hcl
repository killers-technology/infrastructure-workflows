# Linting for every skeleton. The Terraform ruleset catches language mistakes and
# deprecated syntax; the AWS ruleset catches provider mistakes that `validate`
# can't see (invalid instance types, deprecated arguments, wrong enum values).
#
# Pinned here and released with the workflows: a new rule for the whole
# organization is one release.

config {
  call_module_type = "local"
  format           = "compact"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
