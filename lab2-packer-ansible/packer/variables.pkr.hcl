# -----------------------------------------------------------------------------
# AWS Configuration Variables
# -----------------------------------------------------------------------------
variable "aws_region" {
  type        = string
  description = "AWS region to build the AMI in"
  default     = "us-gov-west-1"
}

# Uncomment these if you need to specify VPC/Subnet
# variable "vpc_id" {
#   type        = string
#   description = "VPC ID to launch the builder instance in"
#   default     = ""
# }

# variable "subnet_id" {
#   type        = string
#   description = "Subnet ID to launch the builder instance in"
#   default     = ""
# }

# variable "security_group_id" {
#   type        = string
#   description = "Security group ID for the builder instance"
#   default     = ""
# }

# -----------------------------------------------------------------------------
# AMI Configuration Variables
# -----------------------------------------------------------------------------
variable "ami_prefix" {
  type        = string
  description = "Prefix for the AMI name (your username will be appended)"
  default     = "golden-ami"
}

variable "ami_version" {
  type        = string
  description = "Version tag for the AMI"
  default     = "1.0.0"
}

variable "encrypt_ami" {
  type        = bool
  description = "Whether to encrypt the AMI"
  default     = false
}

# variable "ami_users" {
#   type        = list(string)
#   description = "List of AWS account IDs to share the AMI with"
#   default     = []
# }

# -----------------------------------------------------------------------------
# Instance Configuration Variables
# -----------------------------------------------------------------------------
variable "instance_type" {
  type        = string
  description = "EC2 instance type for the builder"
  default     = "t3.micro"
}

variable "root_volume_size" {
  type        = number
  description = "Size of the root volume in GB"
  default     = 20
}

# -----------------------------------------------------------------------------
# Environment Variables
# -----------------------------------------------------------------------------
variable "environment" {
  type        = string
  description = "Environment tag (lab, dev, staging, prod)"
  default     = "lab"
  
  validation {
    condition     = contains(["lab", "dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: lab, dev, staging, prod."
  }
}
