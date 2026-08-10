###############################################################################
# Spoke side: accept the RAM invitation, then attach the VPC.
#
# Runs in the member account with that account's credentials. Nothing here
# touches transit gateway route tables -- only the owning (hub) account can.
###############################################################################

# Only exists while the org is on the invitation flow. Once
# ram:EnableSharingWithAwsOrganization is on, no invitation is ever created and
# this resource errors with "no invitation found" -- set accept_ram_share=false
# and `terraform state rm` the old resource.
resource "aws_ram_resource_share_accepter" "this" {
  count = var.accept_ram_share ? 1 : 0

  share_arn = var.resource_share_arn
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids

  appliance_mode_support = var.appliance_mode_support ? "enable" : "disable"
  dns_support            = var.dns_support ? "enable" : "disable"
  ipv6_support           = var.ipv6_support ? "enable" : "disable"

  # transit_gateway_default_route_table_association and _propagation are
  # deliberately NOT set. On a RAM-shared transit gateway only the owner
  # account controls association and propagation; the provider cannot manage
  # or drift-detect them from here.

  tags = merge(var.tags, { Name = var.attachment_name })

  # The share must be accepted before the TGW is visible in this account.
  depends_on = [aws_ram_resource_share_accepter.this]
}
