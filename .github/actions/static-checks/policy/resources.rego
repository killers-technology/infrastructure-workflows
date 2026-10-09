# The one-region rule, on the resource side, for a project's skeleton. The rule itself is
# in regions.rego, shared with the module rules.
package terraform

deny contains msg if {
	some msg in data.regions.findings
}
