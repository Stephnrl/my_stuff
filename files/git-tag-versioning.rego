package spacelift

# No-op under Rego v1, required if the policy is evaluated as v0.
import rego.v1

# ---------------------------------------------------------------------------
# Release convention
#
#   Monorepo module   label "tag-prefix:vpc"   tag "vpc/v1.2.0"
#   Flat repo module  no tag-prefix label      tag "v1.2.0"
#
# The label is set by the Terraform module, so this policy is identical for
# every repository and never needs editing when a repo is onboarded.
#
# Every module keeps an independent version counter. A tag only publishes the
# module whose prefix it matches; the semver check below stops a prefixed tag
# from leaking into an unprefixed module in the same repository.
# ---------------------------------------------------------------------------

prefix_labels := {trim_prefix(l, "tag-prefix:") |
	some l in input.module.labels
	startswith(l, "tag-prefix:")
}

default tag_prefix := ""

tag_prefix := sprintf("%s/", [p]) if {
	count(prefix_labels) == 1
	some p in prefix_labels
	p != ""
}

default project_root := ""

project_root := trim(input.module.project_root, "/") if {
	is_string(input.module.project_root)
	input.module.project_root != ""
}

default path_prefix := ""

path_prefix := sprintf("%s/", [project_root]) if project_root != ""

# --- Version publishing ----------------------------------------------------

# The registry only accepts numeric X.Y.Z, so strip the prefix and the "v".
# Both trims are no-ops when tag_prefix is "", which is the flat repo case.
module_version := trim_prefix(trim_prefix(input.push.tag, tag_prefix), "v")

track if {
	input.push.tag != ""
	startswith(input.push.tag, tag_prefix)
	regex.match(`^\d+\.\d+\.\d+$`, module_version)
}

# --- Pull request testing --------------------------------------------------

# Only run tests for the module whose directory the PR actually touches.
# path_prefix is "" for flat repos, so any change counts.
propose if {
	not is_null(input.pull_request)
	affected
}

affected if {
	some filepath in input.push.affected_files
	startswith(trim(filepath, "/"), path_prefix)
}

affected if {
	some filepath in input.pull_request.diff
	startswith(trim(filepath, "/"), path_prefix)
}

# --- Default ---------------------------------------------------------------

ignore if {
	not track
	not propose
}

# Capture real policy inputs in the workbench while tuning. Remove once stable.
sample := true
