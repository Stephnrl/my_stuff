output "job_id" {
  description = "ID of the launched AAP job."
  value       = aap_job.this.id
}

output "job_template_id" {
  description = "Resolved job template ID actually used by the launch."
  value       = local.resolved_job_template_id
}

output "job_status" {
  description = "Final job status when wait_for_completion is true (e.g. successful, failed, canceled)."
  value       = try(aap_job.this.status, null)
}

output "job_url" {
  description = "URL to the job in the AAP UI, when exposed by the provider."
  value       = try(aap_job.this.url, null)
}

output "triggers" {
  description = "Effective triggers map. Use this to verify what would cause a rerun."
  value       = local.triggers
}
