# The one-region rule, on the resource side. Shared by the project rules (package terraform)
# and the module rules (package module).
#
# AWS provider v6 lets any resource or data source override the provider's region
# with its own `region` argument. We don't: a job for us-west-2 must make no API
# call to any other region, so nothing below the provider may pick a region.
package regions

findings contains msg if {
	some file in input
	some kind in ["resource", "data"]
	some type, blocks in file.contents[kind]
	startswith(type, "aws_")
	some name, instances in blocks
	some instance in instances
	"region" in object.keys(instance)
	msg := sprintf(
		"%s: %s %s.%s sets its own region; resources and data sources use the provider's region (one region per run)",
		[file.path, kind, type, name],
	)
}
