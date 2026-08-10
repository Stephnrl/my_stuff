output "attachment_id" {
  description = "Transit gateway VPC attachment ID. The hub needs this for the tgw-routing module."
  value       = aws_ec2_transit_gateway_vpc_attachment.this.id
}

output "vpc_owner_id" {
  description = "Account ID that owns the attached VPC."
  value       = aws_ec2_transit_gateway_vpc_attachment.this.vpc_owner_id
}
