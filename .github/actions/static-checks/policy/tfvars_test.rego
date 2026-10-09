# Unit tests for package tfvars.
# Run with: conftest verify --policy .github/actions/static-checks/policy
package tfvars_test

import data.tfvars

definition(contents) := [{"path": "definitions/prod/us-west-2/terraform.tfvars", "contents": contents}]

good := {"account_id": "111111111111", "region": "us-west-2", "environment": "prod"}

has(substring, contents) if {
	messages := tfvars.deny with input as definition(contents)
	some msg in messages
	contains(msg, substring)
}

test_good_definition_passes if {
	count(tfvars.deny) == 0 with input as definition(good)
}

test_both_regions_pass if {
	count(tfvars.deny) == 0 with input as [
		{"path": "a", "contents": object.union(good, {"region": "us-east-1"})},
		{"path": "b", "contents": good},
	]
}

test_third_region_fails if {
	has("region eu-west-1 is not allowed", object.union(good, {"region": "eu-west-1"}))
}

test_missing_region_fails if {
	has("must set region", object.remove(good, ["region"]))
}

test_missing_account_id_fails if {
	has("must set account_id", object.remove(good, ["account_id"]))
}

test_numeric_account_id_fails if {
	# account_id = 111111111111 (unquoted) would lose leading zeros in some accounts
	has("must set account_id", object.union(good, {"account_id": 111111111111}))
}

test_short_account_id_fails if {
	has("must set account_id", object.union(good, {"account_id": "12345"}))
}

test_every_bad_file_is_reported if {
	count(tfvars.deny) == 2 with input as [
		{"path": "a", "contents": object.union(good, {"region": "eu-west-1"})},
		{"path": "b", "contents": object.remove(good, ["account_id"])},
	]
}
