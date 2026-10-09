# Unit tests for package module.
# Run with: conftest verify --policy .github/actions/static-checks/policy
package module_test

import data.module

versions := {"path": "versions.tf", "contents": {"terraform": [{
	"required_version": ">= 1.10",
	"required_providers": [{"aws": {
		"source": "hashicorp/aws",
		"version": "~> 6.68",
		"configuration_aliases": ["${aws.shared_services_prod}"],
	}}],
}]}}

main(contents) := {"path": "main.tf", "contents": contents}

has(substring, files) if {
	messages := module.deny with input as files
	some msg in messages
	contains(msg, substring)
}

test_plain_module_passes if {
	count(module.deny) == 0 with input as [versions, main({"resource": {"aws_vpc": {"this": [{"cidr_block": "10.0.0.0/16"}]}}})]
}

test_aliased_resource_passes if {
	resources := {"resource": {"aws_ssm_parameter": {"pool": [{"provider": "${aws.shared_services_prod}", "name": "/platform/ipam/pools/us-east-1"}]}}}
	count(module.deny) == 0 with input as [versions, main(resources)]
}

test_provider_block_fails if {
	has("provider \"aws\" is configured inside the module", [versions, main({"provider": {"aws": [{"region": "${var.region}"}]}})])
}

test_backend_fails if {
	has("backend \"s3\" in a module", [{"path": "versions.tf", "contents": {"terraform": [{"backend": {"s3": [{}]}}]}}])
}

test_resource_region_fails if {
	has("resource aws_vpc.this sets its own region", [versions, main({"resource": {"aws_vpc": {"this": [{"region": "us-west-2"}]}}})])
}

test_data_source_region_fails if {
	has("data aws_availability_zones.this sets its own region", [versions, main({"data": {"aws_availability_zones": {"this": [{"region": "${var.region}"}]}}})])
}
