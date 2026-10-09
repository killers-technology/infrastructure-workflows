#!/usr/bin/env bash
# Points the reusable workflows at the actions of the version being released.
#
# The reusable workflows (terraform.yml, module.yml) use this repository's own actions
# by a full reference (killers-technology/infrastructure-workflows/.github/actions/<name>@vX.Y.Z),
# because a called workflow can't use a relative path into its own repository.
# semantic-release runs this script in its prepare step with the new version, then
# commits the result with the changelog and tags that commit. So tag vX.Y.Z only ever
# runs actions from vX.Y.Z.
#
# Usage: scripts/bump-internal-refs.sh <version>     e.g. 3.3.0
set -euo pipefail

version="${1:?usage: bump-internal-refs.sh <version>}"
version="${version#v}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "not a semantic version: $version" >&2
  exit 1
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.."
files=(.github/workflows/terraform.yml .github/workflows/module.yml)
pattern='killers-technology/infrastructure-workflows/\.github/actions/[A-Za-z0-9_-]+@'

# -i.bak works with both GNU and BSD sed.
sed -E -i.bak "s#(${pattern})v[0-9A-Za-z.+-]+#\1v${version}#g" "${files[@]}"
for file in "${files[@]}"; do rm -f "$file.bak"; done

if grep -nE "${pattern}" "${files[@]}" | grep -vF "@v${version}"; then
  echo "some internal refs were not bumped to v${version}" >&2
  exit 1
fi
grep -cE "${pattern}v${version//./\\.}" "${files[@]}" | sed "s/^/bumped to v${version}: /"
