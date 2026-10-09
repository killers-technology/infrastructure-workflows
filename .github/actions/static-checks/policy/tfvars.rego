# What every definition must say about itself.
#
# Input: every definitions/**/terraform.tfvars, parsed with
# `conftest test --parser hcl2 --combine`.
#
# - region: one of the two allowed regions. Nothing else is allowed, ever.
# - account_id: the 12-digit account the definition deploys to, as a string. The
#   pipeline reads it to build the role ARN, and the provider refuses any other account.
package tfvars

allowed_regions := {"us-east-1", "us-west-2"}

deny contains msg if {
	some file in input
	not "region" in object.keys(file.contents)
	msg := sprintf("%s: must set region (one of %s)", [file.path, concat(", ", sort(allowed_regions))])
}

deny contains msg if {
	some file in input
	region := file.contents.region
	not region in allowed_regions
	msg := sprintf(
		"%s: region %v is not allowed; use one of %s",
		[file.path, region, concat(", ", sort(allowed_regions))],
	)
}

deny contains msg if {
	some file in input
	not valid_account_id(file.contents)
	msg := sprintf(
		"%s: must set account_id = \"<12-digit account ID>\"; the pipeline reads it to pick the account and the role",
		[file.path],
	)
}

valid_account_id(contents) if {
	is_string(contents.account_id)
	regex.match(`^[0-9]{12}$`, contents.account_id)
}
