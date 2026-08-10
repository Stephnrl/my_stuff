###############################################################################
# Transit Gateway (netops hub account)
###############################################################################

resource "aws_ec2_transit_gateway" "this" {
  description     = var.description
  amazon_side_asn = var.amazon_side_asn

  # Spoke accounts create attachments; the hub decides whether they land
  # automatically or require an explicit accept in the hub account.
  auto_accept_shared_attachments = var.auto_accept_shared_attachments ? "enable" : "disable"

  # Flat topology     = both true  -> every attachment reaches every other one.
  # Segmented topology = both false -> hub must associate/propagate each
  #                                    attachment explicitly (tgw-routing).
  default_route_table_association = var.default_route_table_association ? "enable" : "disable"
  default_route_table_propagation = var.default_route_table_propagation ? "enable" : "disable"

  dns_support                 = var.dns_support ? "enable" : "disable"
  vpn_ecmp_support            = var.vpn_ecmp_support ? "enable" : "disable"
  transit_gateway_cidr_blocks = var.transit_gateway_cidr_blocks

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    # amazon_side_asn is immutable. Changing it destroys the TGW and every
    # attachment hanging off it across the whole org.
    ignore_changes = [amazon_side_asn]
  }
}

###############################################################################
# Optional segmentation route tables
###############################################################################

resource "aws_ec2_transit_gateway_route_table" "this" {
  for_each = var.route_tables

  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags               = merge(var.tags, each.value.tags, { Name = each.key })
}

###############################################################################
# RAM share
#
# The share is always required for cross-account attachments. Enabling
# org-level sharing only removes the invitation handshake, not the share.
###############################################################################

resource "aws_ram_resource_share" "this" {
  name                      = var.share_name
  allow_external_principals = var.allow_external_principals

  # null lets AWS apply AWSRAMDefaultPermissionTransitGateway.
  permission_arns = var.permission_arns

  tags = merge(var.tags, { Name = var.share_name })
}

resource "aws_ram_resource_association" "tgw" {
  resource_arn       = aws_ec2_transit_gateway.this.arn
  resource_share_arn = aws_ram_resource_share.this.arn
}

# Invitation flow: principals are bare account IDs, so every new spoke is a
# change here. After enabling org sharing you can pass a single OU ARN instead
# and stop touching this input.
resource "aws_ram_principal_association" "this" {
  for_each = var.shared_principals

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.this.arn
}
