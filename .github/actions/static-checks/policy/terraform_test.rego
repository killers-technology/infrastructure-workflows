# Unit tests for package terraform (providers.rego, resources.rego, backend.rego).
# Run with: conftest verify --policy .github/actions/static-checks/policy
package terraform_test

import data.terraform

tags := {"Project": "network", "Environment": "${var.environment}", "ManagedBy": "terraform"}

provider := {
	"region": "${var.region}",
	"allowed_account_ids": ["${var.account_id}"],
	"default_tags": [{"tags": tags}],
}

versions := {"path": "terraform/versions.tf", "contents": {"terraform": [{"backend": {"s3": [{}]}}]}}

providers(blocks) := {"path": "terraform/providers.tf", "contents": {"provider": {"aws": blocks}}}

main(contents) := {"path": "terraform/main.tf", "contents": contents}

skeleton(blocks, contents) := [versions, providers(blocks), main(contents)]

has(substring) if {
	some msg in terraform.deny
	contains(msg, substring)
}

# --- the standard skeleton passes

test_standard_skeleton_passes if {
	count(terraform.deny) == 0 with input as skeleton([provider], {})
}

test_alias_in_the_same_region_passes if {
	# network's prod definitions: a second account, same region, its own OIDC login
	alias := object.union(provider, {"alias": "shared_services", "assume_role_with_web_identity": [{"role_arn": "x"}]})
	count(terraform.deny) == 0 with input as skeleton([provider, alias], {})
}

test_no_aws_provider_passes if {
	# infrastructure-github: the backend is the only AWS thing in it
	count(terraform.deny) == 0 with input as [versions, {"path": "terraform/providers.tf", "contents": {"provider": {"github": [{"owner": "killers-technology"}]}}}]
}

test_tags_from_an_expression_pass_when_the_keys_are_visible if {
	merged := object.union(provider, {"default_tags": [{"tags": "${merge(local.extra_tags, {\n  Project = \"network\"\n  Environment = var.environment\n  ManagedBy = \"terraform\"\n})}"}]})
	count(terraform.deny) == 0 with input as skeleton([merged], {})
}

# --- one region per run

test_hardcoded_region_fails if {
	hardcoded := object.union(provider, {"region": "us-east-1"})
	has("must be region = var.region") with input as skeleton([hardcoded], {})
}

test_second_region_alias_fails if {
	dr := object.union(provider, {"alias": "dr", "region": "us-west-2"})
	has("(alias \"dr\") sets region = us-west-2") with input as skeleton([provider, dr], {})
	count(terraform.deny) == 1 with input as skeleton([provider, dr], {})
}

test_region_from_another_variable_fails if {
	other := object.union(provider, {"region": "${var.dr_region}"})
	has("must be region = var.region") with input as skeleton([other], {})
}

test_missing_region_fails if {
	no_region := object.remove(provider, ["region"])
	has("has no region") with input as skeleton([no_region], {})
}

test_resource_with_its_own_region_fails if {
	resources := {"resource": {"aws_s3_bucket": {"replica": [{"bucket": "x", "region": "us-west-2"}]}}}
	has("resource aws_s3_bucket.replica sets its own region") with input as skeleton([provider], resources)
}

test_data_source_with_its_own_region_fails if {
	data_sources := {"data": {"aws_ami": {"base": [{"region": "${var.region}"}]}}}
	has("data aws_ami.base sets its own region") with input as skeleton([provider], data_sources)
}

test_region_inside_a_nested_block_is_not_the_meta_argument if {
	resources := {"resource": {"aws_dynamodb_table": {"t": [{"name": "t", "replica": [{"region_name": "us-west-2"}]}]}}}
	count(terraform.deny) == 0 with input as skeleton([provider], resources)
}

test_non_aws_resource_with_region_is_ignored if {
	resources := {"resource": {"github_repository_environment": {"prod": [{"region": "x"}]}}}
	count(terraform.deny) == 0 with input as skeleton([provider], resources)
}

# --- mandatory tags

test_missing_default_tags_fails_once_per_tag if {
	untagged := object.remove(provider, ["default_tags"])
	count(terraform.deny) == 3 with input as skeleton([untagged], {})
	has("with ManagedBy through default_tags") with input as skeleton([untagged], {})
}

test_missing_one_tag_fails if {
	partial := object.union(provider, {"default_tags": [{"tags": object.remove(tags, ["Environment"])}]})
	has("with Environment through default_tags") with input as skeleton([partial], {})
	count(terraform.deny) == 1 with input as skeleton([partial], {})
}

test_alias_needs_tags_too if {
	alias := {"alias": "shared_services", "region": "${var.region}"}
	count(terraform.deny) == 3 with input as skeleton([provider, alias], {})
}

test_tags_from_a_local_of_the_skeleton_pass if {
	shared := object.union(provider, {"default_tags": [{"tags": "${local.default_tags}"}]})
	locals := {"locals": [{"default_tags": tags, "other": "${var.x}"}]}
	count(terraform.deny) == 0 with input as skeleton([shared, object.union(shared, {"alias": "b"})], locals)
}

test_local_missing_a_tag_fails if {
	shared := object.union(provider, {"default_tags": [{"tags": "${local.default_tags}"}]})
	locals := {"locals": [{"default_tags": object.remove(tags, ["ManagedBy"])}]}
	has("with ManagedBy through default_tags") with input as skeleton([shared], locals)
	count(terraform.deny) == 1 with input as skeleton([shared], locals)
}

test_undefined_local_fails if {
	shared := object.union(provider, {"default_tags": [{"tags": "${local.default_tags}"}]})
	count(terraform.deny) == 3 with input as skeleton([shared], {})
}

test_opaque_tag_expression_fails if {
	opaque := object.union(provider, {"default_tags": [{"tags": "${var.tags}"}]})
	count(terraform.deny) == 3 with input as skeleton([opaque], {})
}

# --- backend

test_missing_backend_fails if {
	has("must declare backend \"s3\" {}") with input as [providers([provider])]
}

test_other_backend_fails if {
	local := {"path": "terraform/versions.tf", "contents": {"terraform": [{"backend": {"local": [{}]}}]}}
	has("backend \"local\" is not allowed") with input as [local, providers([provider])]
}

test_backend_with_values_fails if {
	full := {"path": "terraform/versions.tf", "contents": {"terraform": [{"backend": {"s3": [{"bucket": "tfstate-network-prod-us-east-1", "key": "terraform.tfstate"}]}}]}}
	has("bucket, key belong in definitions") with input as [full, providers([provider])]
}

test_two_backends_fail if {
	second := {"path": "terraform/backend.tf", "contents": {"terraform": [{"backend": {"s3": [{}]}}]}}
	has("declares 2 backends") with input as [versions, second, providers([provider])]
}
