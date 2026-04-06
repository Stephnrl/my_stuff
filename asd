# oam.tf — Member Account

variable "security_account_id" {
  description = "AWS account ID of the security account"
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

# Provider that assumes into the security account to read SSM
provider "aws" {
  alias  = "security"
  region = "us-gov-west-1"

  assume_role {
    role_arn = "arn:aws-us-gov:iam::${var.security_account_id}:role/oam-ssm-reader"
  }
}

# Read the sink ARN from the security account's SSM
data "aws_ssm_parameter" "sink_arn" {
  provider = aws.security
  name     = "/observability/oam-sink-arn"
}

# Create the link to the security account's sink
resource "aws_oam_link" "this" {
  label_template  = "$AccountName"
  resource_types  = ["AWS::CloudWatch::Metric", "AWS::Logs::LogGroup", "AWS::XRay::Trace"]
  sink_identifier = data.aws_ssm_parameter.sink_arn.value

  link_configuration {
    log_group_configuration {
      filter = "LogGroupName LIKE 'aws/flow-log/%' OR LogGroupName LIKE 'aws/eks/%' OR LogGroupName LIKE 'aws/containerinsights/%'"
    }
  }

  tags = {
    ManagedBy = "terraform"
  }
}

output "oam_link_arn" {
  value = aws_oam_link.this.arn
}
