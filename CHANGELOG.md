# Changelog

## 3.2.0

The version every infrastructure repository in this example pins. Entries above this one are written by semantic-release on each release (see README.md, "Versioning and release").

### Features

* **terraform:** `setup` resolves the project, the environment and the definitions from the pipeline contract (docs/conventions.md)
* **terraform:** global definitions apply first; regional definitions apply in parallel afterwards, even if a global one failed, with `fail-fast: false`
* **terraform:** manual runs take a `region` input (`us-east-1`, `us-west-2` or `global`) to run a single region
* **terraform:** plans are posted on the pull request, one comment per definition, updated on every push
* **terraform:** apply jobs ask for a 4-hour session by default (`role-duration-seconds`)
* **terraform:** callers that pass `MODULES_APP_PRIVATE_KEY` get read-only access to the private module repositories in every job that runs `terraform init` (`module-access`)
* **static-checks:** format and validate, tflint, trivy and conftest policies, including the one-region rule

Not in 3.2.0: `module.yml`, the module checks and the module rules of the policies. They ship with the next minor release, 3.3.0, which the module repositories pin first while the infrastructure repositories stay on 3.2.0.
