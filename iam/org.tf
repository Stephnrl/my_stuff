# Organization-wide Permission Boundary Policy
# This should be created at the organization level and referenced in the IAM module

# Variables for the permission boundary
variable "allowed_regions" {
  description = "List of allowed AWS regions"
  type        = list(string)
  default     = ["us-east-1", "us-west-2"]
}

variable "allowed_instance_types" {
  description = "List of allowed EC2 instance types"
  type        = list(string)
  default     = ["t3.*", "t3a.*", "t4g.*", "m5.*", "m5a.*", "m6i.*", "c5.*", "c5n.*", "r5.*"]
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

resource "aws_iam_policy" "landing_zone_permission_boundary" {
  name        = "LandingZonePermissionBoundary"
  description = "Permission boundary for all landing zone team roles"
  
  policy = templatefile("${path.module}/policies/security/permission-boundary.json", {
    allowed_regions        = var.allowed_regions
    allowed_instance_types = var.allowed_instance_types
  })
  
  tags = merge(var.tags, {
    Name        = "LandingZonePermissionBoundary"
    Purpose     = "OrganizationSecurity"
    ManagedBy   = "Platform"
  })
}

# Output the ARN for use in the IAM foundation module
output "permission_boundary_arn" {
  description = "ARN of the permission boundary policy"
  value       = aws_iam_policy.landing_zone_permission_boundary.arn
}

# Store the permission boundary ARN in SSM for the IAM module to use
resource "aws_ssm_parameter" "permission_boundary_arn" {
  name  = "/landing-zone/permission-boundary-arn"
  type  = "String"
  value = aws_iam_policy.landing_zone_permission_boundary.arn
  
  description = "ARN of the landing zone permission boundary policy"
  
  tags = merge(var.tags, {
    Name      = "PermissionBoundaryArn"
    ManagedBy = "Platform"
  })
}
