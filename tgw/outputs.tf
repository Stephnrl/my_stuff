output "transit_gateway_id" {
  description = "ID of the transit gateway. Pass to the tgw-spoke module."
  value       = aws_ec2_transit_gateway.this.id
}

output "transit_gateway_arn" {
  description = "ARN of the transit gateway."
  value       = aws_ec2_transit_gateway.this.arn
}

output "resource_share_arn" {
  description = "ARN of the RAM share. Spokes need this for the share accepter."
  value       = aws_ram_resource_share.this.arn
}

output "default_association_route_table_id" {
  description = "Default association route table ID."
  value       = aws_ec2_transit_gateway.this.association_default_route_table_id
}

output "default_propagation_route_table_id" {
  description = "Default propagation route table ID."
  value       = aws_ec2_transit_gateway.this.propagation_default_route_table_id
}

output "route_table_ids" {
  description = "Map of segmentation route table name to ID."
  value       = { for k, v in aws_ec2_transit_gateway_route_table.this : k => v.id }
}
