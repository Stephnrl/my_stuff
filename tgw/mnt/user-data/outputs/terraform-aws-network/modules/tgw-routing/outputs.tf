output "attachment_id" {
  description = "The attachment ID being routed."
  value       = local.attachment_id
}

output "association_route_table_id" {
  description = "Route table the attachment is associated with, if any."
  value       = var.associate_route_table_id
}
