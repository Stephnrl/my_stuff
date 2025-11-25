# -----------------------------------------------------------------------------
# Packer Variable Values
# -----------------------------------------------------------------------------
# This file is automatically loaded by Packer.
# Modify these values for your specific build.
# -----------------------------------------------------------------------------

# AWS Region (GovCloud West)
aws_region = "us-gov-west-1"

# AMI Naming
# TODO: Replace <YOUR_USERNAME> with your actual username
ami_prefix  = "golden-ami-<YOUR_USERNAME>"
ami_version = "1.0.0"

# Instance Configuration
instance_type    = "t3.micro"
root_volume_size = 20

# Security
encrypt_ami = false

# Environment
environment = "lab"

# -----------------------------------------------------------------------------
# Network Configuration (Uncomment if required in your environment)
# -----------------------------------------------------------------------------
# vpc_id            = "vpc-xxxxxxxxx"
# subnet_id         = "subnet-xxxxxxxxx"
# security_group_id = "sg-xxxxxxxxx"

# -----------------------------------------------------------------------------
# AMI Sharing (Uncomment to share with other accounts)
# -----------------------------------------------------------------------------
# ami_users = ["123456789012", "987654321098"]
