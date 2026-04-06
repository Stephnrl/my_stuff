# oam.tf — Security Account

variable "org_id" {
  description = "AWS Organization ID"
  type        = string
}

variable "oam_resource_types" {
  type = list(string)
  default = [
    "AWS::CloudWatch::Metric",
    "AWS::Logs::LogGroup",
    "AWS::XRay::Trace",
  ]
}

resource "aws_oam_sink" "this" {
  name = "central-monitoring-sink"

  tags = {
    ManagedBy = "terraform"
  }
}

resource "aws_oam_sink_policy" "this" {
  sink_identifier = aws_oam_sink.this.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Resource  = "*"
        Action    = ["oam:CreateLink", "oam:UpdateLink"]
        Condition = {
          "ForAnyValue:StringEquals" = {
            "aws:PrincipalOrgID" = var.org_id
          }
          "ForAllValues:StringEquals" = {
            "oam:ResourceTypes" = var.oam_resource_types
          }
        }
      }
    ]
  })
}

# Write the sink ARN to SSM
resource "aws_ssm_parameter" "sink_arn" {
  name  = "/observability/oam-sink-arn"
  type  = "String"
  value = aws_oam_sink.this.arn

  tags = {
    ManagedBy = "terraform"
  }
}

# IAM role that member accounts assume to read the SSM parameter
resource "aws_iam_role" "oam_ssm_reader" {
  name = "oam-ssm-reader"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "sts:AssumeRole"
        Condition = {
          "StringEquals" = {
            "aws:PrincipalOrgID" = var.org_id
          }
        }
      }
    ]
  })

  tags = {
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy" "oam_ssm_reader" {
  name = "oam-ssm-reader"
  role = aws_iam_role.oam_ssm_reader.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = aws_ssm_parameter.sink_arn.arn
      }
    ]
  })
}

output "oam_sink_arn" {
  value = aws_oam_sink.this.arn
}

output "ssm_reader_role_arn" {
  description = "Role ARN member accounts assume to read the sink ARN from SSM"
  value       = aws_iam_role.oam_ssm_reader.arn
}
