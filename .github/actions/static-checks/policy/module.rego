# What a module may contain. A module builds in whatever account and region its caller's
# providers point at, so it never configures a provider, a backend or a region of its own.
#
# Input: every *.tf file at the root of a module repository, parsed with
# `conftest test --parser hcl2 --combine`.
#
# - No provider blocks. The caller passes its providers in; a module that needs a second
#   account declares configuration_aliases in required_providers instead.
# - No backend. Only projects have state.
# - No aws_* resource or data source sets its own region (regions.rego).
package module

deny contains msg if {
	some file in input
	some name, _ in file.contents.provider
	msg := sprintf(
		"%s: provider %q is configured inside the module; the caller passes its providers in (configuration_aliases for a second account)",
		[file.path, name],
	)
}

deny contains msg if {
	some file in input
	some block in file.contents.terraform
	some type, _ in block.backend
	msg := sprintf("%s: backend %q in a module; only projects have state", [file.path, type])
}

deny contains msg if {
	some msg in data.regions.findings
}
