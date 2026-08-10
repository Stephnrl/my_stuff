###############################################################################
# Hub-side routing for a spoke attachment.
#
# Runs in the netops account. Route table association and propagation can only
# be performed by the transit gateway owner, which is why this is a separate
# module from tgw-spoke. Skip it entirely if the TGW uses a flat topology
# (default association + propagation enabled).
###############################################################################

resource "aws_ec2_transit_gateway_vpc_attachment_accepter" "this" {
  count = var.accept_attachment ? 1 : 0

  transit_gateway_attachment_id = var.transit_gateway_attachment_id

  # Keep the accepter out of the routing decision; the explicit resources
  # below own it so there is exactly one source of truth.
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(var.tags, { Name = var.attachment_name })
}

locals {
  attachment_id = var.accept_attachment ? aws_ec2_transit_gateway_vpc_attachment_accepter.this[0].id : var.transit_gateway_attachment_id
}

# Which route table this attachment consults when sending traffic.
# An attachment can be associated with exactly one route table.
resource "aws_ec2_transit_gateway_route_table_association" "this" {
  count = var.associate_route_table_id == null ? 0 : 1

  transit_gateway_attachment_id  = local.attachment_id
  transit_gateway_route_table_id = var.associate_route_table_id
}

# Which route tables learn this VPC's CIDRs. Usually more than one:
# the spoke's own table plus any shared-services or inspection table.
resource "aws_ec2_transit_gateway_route_table_propagation" "this" {
  for_each = var.propagate_to_route_table_ids

  transit_gateway_attachment_id  = local.attachment_id
  transit_gateway_route_table_id = each.value
}

# Optional static routes, e.g. 0.0.0.0/0 pointed at an egress or inspection VPC.
resource "aws_ec2_transit_gateway_route" "static" {
  for_each = var.static_routes

  destination_cidr_block         = each.value.destination_cidr_block
  transit_gateway_route_table_id = each.value.route_table_id
  transit_gateway_attachment_id  = local.attachment_id
  blackhole                      = each.value.blackhole
}
