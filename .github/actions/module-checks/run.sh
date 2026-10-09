#!/usr/bin/env bash
# The checks every Terraform module gets on each pull request and before each release:
# format and validate, lint, security scan, the module rules of the organization's
# policies, and the module's own tests. Same tools, same configuration and same pinned
# versions as the project checks: they're read from ../static-checks.
#
# Usage: run.sh [module-dir]     (default: the current directory)
#
# The module-checks action runs it in CI. It runs locally too, with terraform, tflint,
# trivy, conftest and jq on the PATH:
#
#   infrastructure-workflows/.github/actions/module-checks/run.sh terraform-aws-vpc
#
# Tests (tests/*.tftest.hcl or *.tftest.hcl) run without cloud credentials, so they have
# to use mock providers or plan-only runs with overrides.
# Note: validation runs `terraform init -backend=false`, which leaves .terraform behind.
set -o pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
static="$(cd "$here/../static-checks" && pwd)"
cd "${1:-.}" || exit 1

shopt -s nullglob
module_files=(./*.tf)
test_files=(./*.tftest.hcl tests/*.tftest.hcl)
shopt -u nullglob

if [[ ${#module_files[@]} -eq 0 ]]; then
  echo "::error::$(pwd) has no *.tf files at its root"
  exit 1
fi

failed=()

check() {
  local name=$1
  shift
  echo "::group::$name"
  "$@"
  local status=$?
  echo "::endgroup::"
  if [[ $status -ne 0 ]]; then
    echo "::error::$name failed"
    failed+=("$name")
  fi
}

format() {
  terraform fmt -check -recursive -diff .
}

# "aws.shared_services_prod" for every configuration_aliases entry of required_providers.
provider_aliases() {
  conftest parse --parser hcl2 --combine "${module_files[@]}" |
    jq -r '.[].contents.terraform[]?.required_providers[]? | to_entries[]
      | (.value.configuration_aliases? // [])[] | ltrimstr("${") | rtrimstr("}")'
}

# A module that takes a second provider through configuration_aliases can't be validated on
# its own: Terraform wants those provider configurations to exist. Validation declares them,
# empty, in a temporary file that's removed right after.
validate() {
  terraform init -backend=false -input=false -no-color || return 1

  local aliases generated="zz_module_checks_providers.tf" provider alias status
  aliases=$(provider_aliases) || return 1
  if [[ -n "$aliases" ]]; then
    while IFS=. read -r provider alias; do
      printf 'provider "%s" {\n  alias = "%s"\n}\n\n' "$provider" "$alias"
    done <<<"$aliases" >"$generated"
    echo "validating with empty provider blocks for $(tr '\n' ' ' <<<"$aliases")"
  fi

  terraform validate -no-color
  status=$?
  rm -f "$generated"
  return $status
}

lint() {
  tflint --init --config "$static/.tflint.hcl" &&
    tflint --config "$static/.tflint.hcl" --minimum-failure-severity=warning
}

security_scan() {
  trivy config --config "$static/trivy.yaml" --quiet .
}

policies() {
  conftest test --no-color --parser hcl2 --combine --namespace module \
    --policy "$static/policy" "${module_files[@]}"
}

tests() {
  if [[ ${#test_files[@]} -eq 0 ]]; then
    echo "no *.tftest.hcl files: nothing to run"
    return 0
  fi
  terraform test -no-color
}

check "format" format
check "validate" validate
check "lint" lint
check "security scan" security_scan
check "policy checks" policies
check "tests" tests

if [[ ${#failed[@]} -gt 0 ]]; then
  echo "Module checks failed:"
  printf '  - %s\n' "${failed[@]}"
  exit 1
fi
echo "Module checks passed."
