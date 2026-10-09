# The one-region rule and the mandatory tags, on the provider side.
#
# Input: every *.tf file of a skeleton, parsed with `conftest test --parser hcl2 --combine`,
# so `input` is a list of {"path": ..., "contents": ...}. Expressions arrive as their
# source text, e.g. `region = var.region` becomes "${var.region}".
#
# - Every provider "aws" takes its region from the definition: region = var.region.
#   A second region, or a hardcoded one, fails the pull request.
# - Aliases are allowed (network's prod definitions publish the IPAM pool IDs into the two
#   Shared Services accounts, same region), but they follow the same rule, so they can never
#   point at another region.
# - Every provider "aws" tags what it creates with Project, Environment and ManagedBy.
package terraform

region_expression := "${var.region}"

required_tags := {"Project", "Environment", "ManagedBy"}

aws_providers contains {"path": file.path, "provider": provider} if {
	some file in input
	some provider in file.contents.provider.aws
}

deny contains msg if {
	some p in aws_providers
	not p.provider.region
	msg := sprintf(
		"%s: provider \"aws\"%s has no region; set region = var.region (one region per run, chosen by the definition)",
		[p.path, label(p.provider)],
	)
}

deny contains msg if {
	some p in aws_providers
	p.provider.region != region_expression
	msg := sprintf(
		"%s: provider \"aws\"%s sets region = %v; it must be region = var.region (one region per run, chosen by the definition)",
		[p.path, label(p.provider), p.provider.region],
	)
}

deny contains msg if {
	some p in aws_providers
	some tag in required_tags
	not has_default_tag(p.provider, tag)
	msg := sprintf(
		"%s: provider \"aws\"%s must tag everything with %s through default_tags",
		[p.path, label(p.provider), tag],
	)
}

# Written in the provider block: tags = { Project = "network", ... }
has_default_tag(provider, tag) if {
	some block in provider.default_tags
	tags_contain(block.tags, tag)
}

# Shared by several providers through a local of the same skeleton: tags = local.default_tags
has_default_tag(provider, tag) if {
	some block in provider.default_tags
	name := local_reference(block.tags)
	some file in input
	some locals in file.contents.locals
	tags_contain(locals[name], tag)
}

# A literal map.
tags_contain(tags, tag) if {
	is_object(tags)
	tag in object.keys(tags)
}

# An expression, e.g. merge(local.extra, { Project = "network", ... }): the key has to be
# visible in it. A bare reference to something else (a variable, a module) can't be checked.
tags_contain(tags, tag) if {
	is_string(tags)
	regex.match(sprintf(`(^|[^A-Za-z0-9_])"?%s"?\s*=`, [tag]), tags)
}

local_reference(expression) := name if {
	is_string(expression)
	[_, name] := regex.find_all_string_submatch_n(`^\$\{local\.([A-Za-z0-9_-]+)\}$`, expression, 1)[0]
}

label(provider) := sprintf(" (alias %q)", [provider.alias]) if provider.alias

label(provider) := "" if not provider.alias
