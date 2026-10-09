#!/usr/bin/env bash
# Installs the pinned static-check tools on a Linux x86_64 runner and puts them on
# the PATH. Every download is checked against the SHA-256 pinned below, so a tool
# only changes when this file changes, in a release of the workflows.
#
# Usage: install.sh [tool...]    tools: tflint trivy conftest actionlint
#                                (default: tflint trivy conftest)
set -euo pipefail

version() {
  case $1 in
    tflint) echo 0.64.0 ;;
    trivy) echo 0.74.0 ;;
    conftest) echo 0.70.1 ;;
    actionlint) echo 1.7.12 ;;
    *) echo "unknown tool: $1" >&2 && return 1 ;;
  esac
}

sha256() {
  case $1 in
    tflint) echo cca9d13e2e1d7a2c627af60ff899a3c9b74212899416aeb96ec764d2ef954537 ;;
    trivy) echo 2ae6fe3ee734b7fdf11335663e18c75ea12dccc76062f09f164a3b0f8be4371a ;;
    conftest) echo 613d124b8f6c1f3cee890491f7ab19114cca5a2102ca47cb2e6c35b4c23f9c8a ;;
    actionlint) echo 8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8 ;;
  esac
}

url() {
  local v
  v=$(version "$1")
  case $1 in
    tflint) echo "https://github.com/terraform-linters/tflint/releases/download/v$v/tflint_linux_amd64.zip" ;;
    trivy) echo "https://github.com/aquasecurity/trivy/releases/download/v$v/trivy_${v}_Linux-64bit.tar.gz" ;;
    conftest) echo "https://github.com/open-policy-agent/conftest/releases/download/v$v/conftest_${v}_Linux_x86_64.tar.gz" ;;
    actionlint) echo "https://github.com/rhysd/actionlint/releases/download/v$v/actionlint_${v}_linux_amd64.tar.gz" ;;
  esac
}

if [[ "$(uname -s)/$(uname -m)" != "Linux/x86_64" ]]; then
  echo "::error::the static-check tools are pinned for Linux x86_64 runners"
  exit 1
fi

work_dir="${RUNNER_TEMP:?}/static-checks"
bin_dir="$work_dir/bin"
mkdir -p "$bin_dir"

tools=("$@")
if [[ ${#tools[@]} -eq 0 ]]; then
  tools=(tflint trivy conftest)
fi

for tool in "${tools[@]}"; do
  source_url=$(url "$tool")
  archive="$work_dir/$(basename "$source_url")"
  curl -sSfL --retry 3 -o "$archive" "$source_url"
  echo "$(sha256 "$tool")  $archive" | sha256sum --check --strict -
  case $archive in
    *.zip) unzip -o -q "$archive" "$tool" -d "$bin_dir" ;;
    *) tar -xzf "$archive" -C "$bin_dir" "$tool" ;;
  esac
  echo "installed $tool $(version "$tool")"
done

echo "$bin_dir" >>"${GITHUB_PATH:?}"
