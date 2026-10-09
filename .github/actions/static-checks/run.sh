#!/usr/bin/env bash
# The static checks every Terraform project gets before any plan, in the order the
# article lists them: format and validate, lint, security scan, policy checks.
#
# Usage: run.sh [project-dir]     (default: the current directory)
#
# The static-checks action runs it in CI. It runs locally too, with terraform,
# tflint, trivy and conftest on the PATH:
#
#   infrastructure-workflows/.github/actions/static-checks/run.sh infrastructure-aws-network
#
# Every check runs even when an earlier one fails, so one push shows every problem.
# Lint and security scan run once per definition, with that definition's terraform.tfvars.
# Note: validation runs `terraform init -backend=false`, which leaves terraform/.terraform behind.
set -o pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${1:-.}" || exit 1

if [[ ! -d terraform || ! -d definitions ]]; then
  echo "::error::$(pwd) needs a terraform/ and a definitions/ folder (repository layout, docs/conventions.md)"
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
  terraform fmt -check -recursive -diff terraform &&
    terraform fmt -check -recursive -diff definitions
}

validate() {
  terraform -chdir=terraform init -backend=false -input=false -no-color &&
    terraform -chdir=terraform validate -no-color
}

# Lint and scan the skeleton the way each definition runs it: with that definition's values,
# so a resource that only a global (or only a regional) definition creates is checked too, and
# expressions over variables without defaults can be evaluated.
var_files=()
while IFS= read -r -d '' file; do
  var_file="$(dirname "$file")/terraform.tfvars"
  [[ -f "$var_file" ]] && var_files+=("$PWD/$var_file")
done < <(find definitions -type f -name backend.hcl -print0 | sort -z)

lint() {
  tflint --init --config "$here/.tflint.hcl" || return 1
  if [[ ${#var_files[@]} -eq 0 ]]; then
    tflint --chdir terraform --config "$here/.tflint.hcl" --minimum-failure-severity=warning
    return
  fi
  local status=0 var_file
  for var_file in "${var_files[@]}"; do
    echo "--- ${var_file#"$PWD/"}"
    tflint --chdir terraform --config "$here/.tflint.hcl" --minimum-failure-severity=warning \
      --var-file "$var_file" || status=1
  done
  return $status
}

security_scan() {
  if [[ ${#var_files[@]} -eq 0 ]]; then
    trivy config --config "$here/trivy.yaml" --quiet terraform
    return
  fi
  local status=0 var_file
  for var_file in "${var_files[@]}"; do
    echo "--- ${var_file#"$PWD/"}"
    trivy config --config "$here/trivy.yaml" --quiet --tf-vars "$var_file" terraform || status=1
  done
  return $status
}

policies() {
  local skeleton=() definitions=() file
  while IFS= read -r -d '' file; do skeleton+=("$file"); done \
    < <(find terraform -maxdepth 1 -type f -name '*.tf' -print0 | sort -z)
  while IFS= read -r -d '' file; do definitions+=("$file"); done \
    < <(find definitions -type f -name terraform.tfvars -print0 | sort -z)

  if [[ ${#skeleton[@]} -eq 0 || ${#definitions[@]} -eq 0 ]]; then
    echo "no terraform/*.tf or definitions/**/terraform.tfvars to check"
    return 1
  fi

  # --combine: the rules look across files (exactly one backend, in whichever file).
  conftest test --no-color --parser hcl2 --combine --namespace terraform \
    --policy "$here/policy" "${skeleton[@]}"
  local skeleton_status=$?
  conftest test --no-color --parser hcl2 --combine --namespace tfvars \
    --policy "$here/policy" "${definitions[@]}"
  local definitions_status=$?
  [[ $skeleton_status -eq 0 && $definitions_status -eq 0 ]]
}

check "format" format
check "validate" validate
check "lint" lint
check "security scan" security_scan
check "policy checks" policies

if [[ ${#failed[@]} -gt 0 ]]; then
  echo "Static checks failed:"
  printf '  - %s\n' "${failed[@]}"
  exit 1
fi
echo "Static checks passed."
