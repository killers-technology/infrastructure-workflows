"""Unit tests for .github/actions/resolve/resolve.py.

Run from the repository root:  python3 -m unittest discover -s tests -v
"""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("resolve", ROOT / ".github/actions/resolve/resolve.py")
resolve = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(resolve)

ACCOUNTS = {
    "development": "222222222222",
    "staging": "888888888888",
    "non-prod": "444444444444",
    "prod": "111111111111",
}


def make_repository(root: Path, definitions: dict) -> Path:
    """definitions: {"prod/us-east-1": {"region": "us-east-1"}, ...}; account from the environment."""
    for path, values in definitions.items():
        directory = root / "definitions" / path
        directory.mkdir(parents=True)
        (directory / "backend.hcl").write_text('bucket = "tfstate"\n')
        values = {"account_id": ACCOUNTS[path.split("/")[0]], **values}
        lines = [f'{name} = "{value}"' for name, value in values.items() if value is not None]
        (directory / "terraform.tfvars").write_text("\n".join(lines) + "\n")
    return root


PLATFORM = {
    "non-prod/global": {"region": "us-east-1", "scope": "global"},
    "non-prod/us-east-1": {"region": "us-east-1"},
    "prod/global": {"region": "us-east-1", "scope": "global"},
    "prod/us-east-1": {"region": "us-east-1"},
    "prod/us-west-2": {"region": "us-west-2"},
}
WORKLOAD = {
    "development/global": {"region": "us-east-1"},
    "development/us-east-1": {"region": "us-east-1"},
    "staging/global": {"region": "us-east-1"},
    "staging/us-east-1": {"region": "us-east-1"},
    "prod/global": {"region": "us-east-1"},
    "prod/us-east-1": {"region": "us-east-1"},
    "prod/us-west-2": {"region": "us-west-2"},
}
SINGLE = {
    "prod/us-east-1": {"region": "us-east-1"},
    "prod/us-west-2": {"region": "us-west-2"},
}
# infrastructure-aws-management: definitions/<env>/<account>/<global|region>/, every account
# in its own definitions, the pipeline running as platform-pipeline(-plan) in each of them.
MANAGEMENT = {
    "prod/management/global": {"region": "us-east-1", "account_id": "301697000338"},
    "prod/management/us-east-1": {"region": "us-east-1", "account_id": "301697000338"},
    "prod/management/us-west-2": {"region": "us-west-2", "account_id": "301697000338"},
    "prod/network-prod/global": {"region": "us-east-1", "account_id": "111111111111"},
    "prod/shared-services-prod/global": {"region": "us-east-1", "account_id": "555555555555"},
    "prod/shared-services-prod/us-east-1": {"region": "us-east-1", "account_id": "555555555555"},
    "prod/shared-services-prod/us-west-2": {"region": "us-west-2", "account_id": "555555555555"},
    "non-prod/network-non-prod/global": {"region": "us-east-1", "account_id": "444444444444"},
    "non-prod/shared-services-non-prod/global": {"region": "us-east-1", "account_id": "333333333333"},
    "non-prod/shared-services-non-prod/us-east-1": {"region": "us-east-1", "account_id": "333333333333"},
}


class ResolveTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def run_resolve(self, layout, repository="killers-technology/infrastructure-aws-network", **event):
        workspace = make_repository(self.tmp / "repo", layout)
        env = {"REPOSITORY": repository, "REF_TYPE": "branch", **event}
        result = resolve.resolve(env, workspace)
        for key in ("definitions", "global", "regional"):
            result[key] = json.loads(result[key])
        return result

    @staticmethod
    def paths(definitions):
        return [d["path"] for d in definitions]

    # Branch -> environment, platform repositories
    def test_platform_pr_into_development_plans_non_prod(self):
        r = self.run_resolve(PLATFORM, EVENT_NAME="pull_request", BASE_REF="development", REF_NAME="7/merge")
        self.assertEqual((r["kind"], r["mode"], r["environment"]), ("platform", "plan", "non-prod"))
        self.assertEqual(self.paths(r["definitions"]), ["non-prod/global", "non-prod/us-east-1"])
        self.assertEqual(r["definitions"][0]["role_arn"], "arn:aws:iam::444444444444:role/github-network-plan")

    def test_platform_push_to_main_applies_prod_global_first(self):
        r = self.run_resolve(PLATFORM, EVENT_NAME="push", REF_NAME="main")
        self.assertEqual((r["mode"], r["environment"], r["role"]), ("apply", "prod", "github-network-apply"))
        self.assertEqual(self.paths(r["global"]), ["prod/global"])
        self.assertEqual(self.paths(r["regional"]), ["prod/us-east-1", "prod/us-west-2"])
        self.assertEqual(r["global"][0]["region"], "us-east-1")
        self.assertEqual(r["regional"][1]["region"], "us-west-2")

    def test_platform_push_to_release_does_nothing(self):
        r = self.run_resolve(PLATFORM, EVENT_NAME="push", REF_NAME="release/1.4")
        self.assertEqual((r["mode"], r["environment"], r["definitions"]), ("none", "", []))

    def test_feature_branch_pr_only_runs_checks(self):
        r = self.run_resolve(PLATFORM, EVENT_NAME="pull_request", BASE_REF="feature/x", REF_NAME="8/merge")
        self.assertEqual(r["mode"], "none")

    # Workload
    def test_workload_environments(self):
        cases = [
            ("pull_request", "development", "plan", "development"),
            ("push", "development", "apply", "development"),
            ("push", "release/1.4", "apply", "staging"),
            ("pull_request", "release/1.4", "plan", "staging"),
            ("pull_request", "main", "plan", "prod"),
            ("push", "main", "apply", "prod"),
        ]
        for event, branch, mode, environment in cases:
            with self.subTest(event=event, branch=branch):
                self.tearDown()
                self.setUp()
                ref = {"BASE_REF": branch, "REF_NAME": "1/merge"} if event == "pull_request" else {"REF_NAME": branch}
                r = self.run_resolve(
                    WORKLOAD, repository="killers-technology/infrastructure-aws-workload", EVENT_NAME=event, **ref
                )
                self.assertEqual((r["kind"], r["mode"], r["environment"]), ("workload", mode, environment))
                self.assertTrue(all(d["path"].startswith(environment + "/") for d in r["definitions"]))

    def test_workload_staging_account_and_role(self):
        r = self.run_resolve(
            WORKLOAD, repository="killers-technology/infrastructure-aws-workload", EVENT_NAME="push", REF_NAME="release/1.4"
        )
        self.assertEqual(r["regional"][0]["role_arn"], "arn:aws:iam::888888888888:role/github-workload-apply")

    # Single-environment repositories
    def test_single_env(self):
        cases = [
            ("pull_request", "development", "plan", "prod"),
            ("push", "development", "none", ""),
            ("pull_request", "main", "plan", "prod"),
            ("push", "main", "apply", "prod"),
        ]
        for event, branch, mode, environment in cases:
            with self.subTest(event=event, branch=branch):
                self.tearDown()
                self.setUp()
                ref = {"BASE_REF": branch, "REF_NAME": "1/merge"} if event == "pull_request" else {"REF_NAME": branch}
                r = self.run_resolve(SINGLE, repository="killers-technology/infrastructure-aws-logs", EVENT_NAME=event, **ref)
                self.assertEqual((r["kind"], r["mode"], r["environment"]), ("single-env", mode, environment))

    def test_github_project_name(self):
        r = self.run_resolve(
            {"prod/us-east-1": {"region": "us-east-1"}},
            repository="killers-technology/infrastructure-github",
            EVENT_NAME="push",
            REF_NAME="main",
        )
        self.assertEqual(r["project"], "github")
        self.assertEqual(r["regional"][0]["role_arn"], "arn:aws:iam::111111111111:role/github-github-apply")

    # Manual runs
    def test_dispatch_single_region(self):
        r = self.run_resolve(PLATFORM, EVENT_NAME="workflow_dispatch", REF_NAME="main", REGION_INPUT="us-west-2")
        self.assertEqual((r["mode"], r["environment"]), ("apply", "prod"))
        self.assertEqual(r["global"], [])
        self.assertEqual(self.paths(r["regional"]), ["prod/us-west-2"])

    def test_dispatch_global_only(self):
        r = self.run_resolve(PLATFORM, EVENT_NAME="workflow_dispatch", REF_NAME="main", REGION_INPUT="global")
        self.assertEqual(self.paths(r["global"]), ["prod/global"])
        self.assertEqual(r["regional"], [])

    def test_dispatch_without_region_runs_everything(self):
        r = self.run_resolve(PLATFORM, EVENT_NAME="workflow_dispatch", REF_NAME="main")
        self.assertEqual(len(r["definitions"]), 3)

    def test_dispatch_rejects_unknown_region(self):
        with self.assertRaises(resolve.ResolveError):
            self.run_resolve(PLATFORM, EVENT_NAME="workflow_dispatch", REF_NAME="main", REGION_INPUT="eu-west-1")

    def test_region_input_ignored_outside_dispatch(self):
        r = self.run_resolve(PLATFORM, EVENT_NAME="push", REF_NAME="main", REGION_INPUT="us-west-2")
        self.assertEqual(len(r["definitions"]), 3)

    def test_dispatch_for_a_region_without_definitions_does_nothing(self):
        r = self.run_resolve(
            {"prod/us-east-1": {"region": "us-east-1"}},
            repository="killers-technology/infrastructure-github",
            EVENT_NAME="workflow_dispatch",
            REF_NAME="main",
            REGION_INPUT="us-west-2",
        )
        self.assertEqual((r["mode"], r["environment"], r["definitions"]), ("none", "", []))

    def test_dispatch_from_tag_does_nothing(self):
        r = self.run_resolve(PLATFORM, EVENT_NAME="workflow_dispatch", REF_NAME="v1.0.0", REF_TYPE="tag")
        self.assertEqual(r["mode"], "none")

    # Management: one folder per account, global and regional definitions in each, role names overridden
    def run_management(self, **event):
        return self.run_resolve(
            MANAGEMENT,
            repository="killers-technology/infrastructure-aws-management",
            APPLY_ROLE="platform-pipeline",
            PLAN_ROLE="platform-pipeline-plan",
            **event,
        )

    def test_management_push_to_main_per_account_layout(self):
        r = self.run_management(EVENT_NAME="push", REF_NAME="main")
        self.assertEqual((r["kind"], r["mode"], r["environment"], r["role"]), ("platform", "apply", "prod", "platform-pipeline"))
        self.assertEqual(
            self.paths(r["global"]),
            ["prod/management/global", "prod/network-prod/global", "prod/shared-services-prod/global"],
        )
        self.assertEqual(
            self.paths(r["regional"]),
            [
                "prod/management/us-east-1",
                "prod/management/us-west-2",
                "prod/shared-services-prod/us-east-1",
                "prod/shared-services-prod/us-west-2",
            ],
        )
        self.assertTrue(all(d["region"] == "us-east-1" for d in r["global"]))
        roles = {d["path"]: d["role_arn"] for d in r["definitions"]}
        self.assertEqual(roles["prod/network-prod/global"], "arn:aws:iam::111111111111:role/platform-pipeline")
        self.assertEqual(roles["prod/shared-services-prod/us-west-2"], "arn:aws:iam::555555555555:role/platform-pipeline")

    def test_management_pr_into_development_plans_every_non_prod_account(self):
        r = self.run_management(EVENT_NAME="pull_request", BASE_REF="development", REF_NAME="4/merge")
        self.assertEqual((r["mode"], r["environment"]), ("plan", "non-prod"))
        self.assertEqual(
            sorted({d["role_arn"] for d in r["definitions"]}),
            [
                "arn:aws:iam::333333333333:role/platform-pipeline-plan",
                "arn:aws:iam::444444444444:role/platform-pipeline-plan",
            ],
        )

    def test_management_dispatch_one_region_across_accounts(self):
        r = self.run_management(EVENT_NAME="workflow_dispatch", REF_NAME="main", REGION_INPUT="us-west-2")
        self.assertEqual(r["global"], [])
        self.assertEqual(self.paths(r["regional"]), ["prod/management/us-west-2", "prod/shared-services-prod/us-west-2"])

    # Contract violations fail the run
    def test_missing_account_id(self):
        with self.assertRaisesRegex(resolve.ResolveError, "account_id"):
            self.run_resolve(
                {"prod/us-east-1": {"region": "us-east-1", "account_id": None}}, EVENT_NAME="push", REF_NAME="main"
            )

    def test_region_mismatch(self):
        with self.assertRaisesRegex(resolve.ResolveError, "folder says"):
            self.run_resolve({"prod/us-west-2": {"region": "us-east-1"}}, EVENT_NAME="push", REF_NAME="main")

    def test_global_outside_primary_region(self):
        with self.assertRaisesRegex(resolve.ResolveError, "global definitions"):
            self.run_resolve({"prod/global": {"region": "us-west-2"}}, EVENT_NAME="push", REF_NAME="main")

    def test_region_not_allowed(self):
        with self.assertRaisesRegex(resolve.ResolveError, "not one of"):
            self.run_resolve({"prod/eu-west-1": {"region": "eu-west-1"}}, EVENT_NAME="push", REF_NAME="main")

    def test_bad_repository_name(self):
        with self.assertRaises(resolve.ResolveError):
            self.run_resolve(SINGLE, repository="killers-technology/network", EVENT_NAME="push", REF_NAME="main")

    def test_folders_without_backend_are_not_definitions(self):
        workspace = make_repository(self.tmp / "repo", SINGLE)
        (workspace / "definitions/prod/notes").mkdir()
        r = resolve.resolve({"REPOSITORY": "killers-technology/infrastructure-aws-logs", "EVENT_NAME": "push", "REF_NAME": "main"}, workspace)
        self.assertEqual(len(json.loads(r["definitions"])), 2)

    def test_nested_region_values_are_ignored(self):
        workspace = make_repository(self.tmp / "repo", {"prod/us-east-1": {"region": "us-east-1"}})
        tfvars = workspace / "definitions/prod/us-east-1/terraform.tfvars"
        tfvars.write_text(tfvars.read_text() + 'peer = {\n  region = "us-west-2"\n}\n')
        r = resolve.resolve({"REPOSITORY": "killers-technology/infrastructure-aws-network", "EVENT_NAME": "push", "REF_NAME": "main"}, workspace)
        self.assertEqual(json.loads(r["regional"])[0]["region"], "us-east-1")


if __name__ == "__main__":
    unittest.main()
