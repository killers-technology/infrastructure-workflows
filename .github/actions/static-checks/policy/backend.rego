# The skeleton has no environment knowledge, and that includes where its state lives.
#
# Exactly one backend, of type s3, with an empty body: bucket, key, region and locking
# come from definitions/<env>/<region>/backend.hcl through -backend-config.
package terraform

backends contains {"path": file.path, "type": type, "config": config} if {
	some file in input
	some block in file.contents.terraform
	some type, configs in block.backend
	some config in configs
}

deny contains msg if {
	count(backends) == 0
	msg := "the skeleton must declare backend \"s3\" {} (partial configuration, completed by definitions/<env>/<region>/backend.hcl)"
}

deny contains msg if {
	count(backends) > 1
	msg := sprintf("the skeleton declares %d backends; it must declare exactly one, backend \"s3\" {}", [count(backends)])
}

deny contains msg if {
	some b in backends
	b.type != "s3"
	msg := sprintf("%s: backend %q is not allowed; state lives in S3, declared as backend \"s3\" {}", [b.path, b.type])
}

deny contains msg if {
	some b in backends
	b.type == "s3"
	count(b.config) > 0
	msg := sprintf(
		"%s: backend \"s3\" must be empty (partial configuration); %s belong in definitions/<env>/<region>/backend.hcl",
		[b.path, concat(", ", sort(object.keys(b.config)))],
	)
}
