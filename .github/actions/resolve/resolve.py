#!/usr/bin/env python3
"""Work out what one pipeline run does.

This is the `setup` job of the central workflow. From the GitHub event and the
caller's repository layout it answers four questions:

  * which project is this?            the repository name
  * which environment, plan or apply? the event and the branch
  * which definitions?                every folder under definitions/<env>/ with a backend.hcl
  * which role, in which account?     account_id from each definition's terraform.tfvars

The rules are the pipeline contract in docs/conventions.md. Standard library
only, so it runs on any runner and can be run locally:

    EVENT_NAME=push REF_NAME=main REPOSITORY=killers-technology/infrastructure-aws-network \\
        python3 resolve.py path/to/infrastructure-aws-network
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

REGIONS = ("us-east-1", "us-west-2")
GLOBAL_REGION = "us-east-1"  # global services are applied from the primary region
PROJECT_PREFIXES = ("infrastructure-aws-", "infrastructure-")

# Folder names end up in shell commands, job names and concurrency groups.
SEGMENT = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
ACCOUNT_ID = re.compile(r"^\d{12}$")
# Top-level assignments only: `terraform fmt` puts them in column 0, nested ones are indented.
TFVARS_STRING = re.compile(r'^(?P<name>[a-z_]+)\s*=\s*"(?P<value>[^"]*)"', re.MULTILINE)


class ResolveError(Exception):
    """The repository doesn't follow the pipeline contract."""


def project_name(repository: str) -> str:
    """`killers-technology/infrastructure-aws-network` -> `network`, `killers-technology/infrastructure-github` -> `github`."""
    name = repository.rsplit("/", 1)[-1]
    for prefix in PROJECT_PREFIXES:
        if name.startswith(prefix) and len(name) > len(prefix):
            return name[len(prefix):]
    raise ResolveError(
        f"repository '{name}' should be named infrastructure-aws-<project> or infrastructure-<project>"
    )


def repository_kind(definitions: Path) -> str:
    """Which environments the repository has, from the folders under definitions/.

    workload    development, staging, prod
    platform    non-prod, prod
    single-env  prod only
    """
    environments = {p.name for p in definitions.iterdir() if p.is_dir()} if definitions.is_dir() else set()
    if environments & {"development", "staging"}:
        return "workload"
    if "non-prod" in environments:
        return "platform"
    return "single-env"


def environment_for(kind: str, mode: str, branch: str) -> str | None:
    """The branch -> environment table of the pipeline contract.

    `branch` is the branch a pull request targets (mode "plan") or the branch
    that was pushed or run by hand (mode "apply").
    """
    if branch == "main":
        return "prod"
    if branch == "development":
        if kind == "workload":
            return "development"
        if kind == "platform":
            return "non-prod"
        # Single-environment repositories still take changes through development,
        # and plan them against prod. Nothing is applied until main.
        return "prod" if mode == "plan" else None
    if branch.startswith("release/") and kind == "workload":
        return "staging"
    return None


def target(kind: str, event: str, base_ref: str, ref_name: str, ref_type: str) -> tuple[str, str | None]:
    """(mode, environment) for this run. Mode is plan, apply or none."""
    if event == "pull_request":
        mode, branch = "plan", base_ref
    elif event in ("push", "workflow_dispatch") and ref_type in ("branch", ""):
        mode, branch = "apply", ref_name
    else:
        return "none", None
    environment = environment_for(kind, mode, branch)
    return (mode, environment) if environment else ("none", None)


def read_tfvars(path: Path) -> dict[str, str]:
    """The top-level string assignments of a terraform.tfvars file."""
    values: dict[str, str] = {}
    for match in TFVARS_STRING.finditer(path.read_text(encoding="utf-8")):
        values.setdefault(match["name"], match["value"])
    return values


def discover(definitions: Path, environment: str, role: str) -> list[dict[str, str]]:
    """Every definition of one environment, in a stable order."""
    root = definitions / environment
    if not root.is_dir():
        return []

    found = []
    for backend in sorted(root.rglob("backend.hcl")):
        directory = backend.parent
        relative = directory.relative_to(definitions)
        path = relative.as_posix()
        for segment in relative.parts:
            if not SEGMENT.match(segment):
                raise ResolveError(f"definitions/{path}: folder name '{segment}' has characters the pipeline won't use")

        scope = "global" if "global" in relative.parts[1:] else "regional"

        tfvars = directory / "terraform.tfvars"
        if not tfvars.is_file():
            raise ResolveError(f"definitions/{path}: has a backend.hcl but no terraform.tfvars")
        values = read_tfvars(tfvars)

        account_id = values.get("account_id", "")
        if not ACCOUNT_ID.match(account_id):
            raise ResolveError(f'definitions/{path}/terraform.tfvars: needs account_id = "<12 digits>"')

        path_region = next((p for p in relative.parts if p in REGIONS), None)
        region = values.get("region") or path_region or (GLOBAL_REGION if scope == "global" else None)
        if region not in REGIONS:
            raise ResolveError(f"definitions/{path}: region '{region}' is not one of {', '.join(REGIONS)}")
        if scope == "global" and region != GLOBAL_REGION:
            raise ResolveError(f"definitions/{path}: global definitions run from {GLOBAL_REGION}, not {region}")
        if path_region and path_region != region:
            raise ResolveError(f"definitions/{path}: the folder says {path_region} but terraform.tfvars says {region}")

        found.append(
            {
                "path": path,
                "scope": scope,
                "region": region,
                "account_id": account_id,
                "role_arn": f"arn:aws:iam::{account_id}:role/{role}",
            }
        )
    return found


def filter_region(definitions: list[dict[str, str]], region: str) -> list[dict[str, str]]:
    """A manual run for one region runs that region's regional definitions and nothing else.

    `global` is accepted too, to re-run only the global definitions.
    """
    if not region:
        return definitions
    if region == "global":
        return [d for d in definitions if d["scope"] == "global"]
    if region in REGIONS:
        return [d for d in definitions if d["scope"] == "regional" and d["region"] == region]
    raise ResolveError(f"region input '{region}' should be one of {', '.join(REGIONS)} or global")


def resolve(env: dict[str, str], workspace: Path) -> dict[str, str]:
    project = project_name(env.get("REPOSITORY", ""))
    definitions_root = workspace / "definitions"
    kind = repository_kind(definitions_root)
    event = env.get("EVENT_NAME", "")
    mode, environment = target(
        kind, event, env.get("BASE_REF", ""), env.get("REF_NAME", ""), env.get("REF_TYPE", "")
    )

    role = ""
    selected: list[dict[str, str]] = []
    if mode != "none":
        role = env.get(f"{mode.upper()}_ROLE") or f"github-{project}-{mode}"
        selected = discover(definitions_root, environment, role)
        if event == "workflow_dispatch":
            selected = filter_region(selected, env.get("REGION_INPUT", "").strip())
        if not selected:
            mode, environment = "none", None

    global_definitions = [d for d in selected if d["scope"] == "global"]
    regional_definitions = [d for d in selected if d["scope"] == "regional"]
    return {
        "project": project,
        "kind": kind,
        "mode": mode,
        "environment": environment or "",
        "role": role,
        "definitions": json.dumps(selected),
        "global": json.dumps(global_definitions),
        "regional": json.dumps(regional_definitions),
    }


def summary(result: dict[str, str]) -> str:
    lines = [f"### {result['project']}: {result['mode']} {result['environment']}".rstrip(), ""]
    definitions = json.loads(result["definitions"])
    if not definitions:
        lines.append("Nothing to plan or apply for this event. Only the static checks run.")
        return "\n".join(lines) + "\n"
    lines += ["| Definition | Scope | Region | Role |", "|---|---|---|---|"]
    for d in definitions:
        lines.append(f"| `{d['path']}` | {d['scope']} | {d['region']} | `{d['role_arn']}` |")
    return "\n".join(lines) + "\n"


def main() -> int:
    workspace = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    try:
        result = resolve(dict(os.environ), workspace)
    except ResolveError as error:
        print(f"::error::{error}")
        return 1

    for name, value in result.items():
        print(f"{name}={value}")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            for name, value in result.items():
                output.write(f"{name}={value}\n")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as step_summary:
            step_summary.write(summary(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
