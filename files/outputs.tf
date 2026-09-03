output "space_id" {
  description = "ID of the space the modules live in."
  value       = local.space_id
}

output "policy_id" {
  description = "ID of the tag-driven versioning policy, or null when create_policy is false."
  value       = var.create_policy ? spacelift_policy.git_tag_versioning[0].id : null
}

output "module_ids" {
  description = "Spacelift module IDs (slugs), keyed the same as the internal module map."
  value       = { for k, m in spacelift_module.this : k => m.id }
}

output "module_sources" {
  description = "Source addresses to paste into consuming stacks."
  value = {
    for k, m in local.modules :
    k => "spacelift.io/${data.spacelift_account.this.name}/${m.name}/${m.terraform_provider}"
  }
}

output "release_commands" {
  description = "How to cut a release for each module. Substitute the real version."
  value = {
    for k, m in local.modules :
    k => m.tag_prefix != "" ? "git tag ${m.tag_prefix}/vX.Y.Z && git push origin ${m.tag_prefix}/vX.Y.Z" : "git tag vX.Y.Z && git push origin vX.Y.Z"
  }
}
