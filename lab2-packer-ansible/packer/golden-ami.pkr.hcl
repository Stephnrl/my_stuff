packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

# -----------------------------------------------------------------------------
# Local Variables
# -----------------------------------------------------------------------------
locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
  ami_name  = "${var.ami_prefix}-${local.timestamp}"
  
  common_tags = {
    Name        = local.ami_name
    Environment = var.environment
    Builder     = "packer"
    BuildDate   = timestamp()
    BaseAMI     = "amazon-linux-2"
  }
}

# -----------------------------------------------------------------------------
# Source: Amazon EBS-backed AMI
# -----------------------------------------------------------------------------
source "amazon-ebs" "golden" {
  # AMI Configuration
  ami_name        = local.ami_name
  ami_description = "Golden AMI built with Packer and Ansible - ${timestamp()}"
  
  # Instance Configuration
  instance_type = var.instance_type
  region        = var.aws_region
  
  # Source AMI - dynamically find the latest Amazon Linux 2
  source_ami_filter {
    filters = {
      name                = "amzn2-ami-hvm-*-x86_64-gp2"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["amazon"]
    most_recent = true
  }
  
  # SSH Configuration
  ssh_username         = "ec2-user"
  ssh_timeout          = "10m"
  ssh_interface        = "public_ip"
  
  # Network Configuration (uncomment and set if needed)
  # vpc_id               = var.vpc_id
  # subnet_id            = var.subnet_id
  # security_group_id    = var.security_group_id
  # associate_public_ip_address = true
  
  # EBS Configuration
  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = var.encrypt_ami
  }
  
  # Tags
  tags = merge(local.common_tags, {
    Version = var.ami_version
  })
  
  run_tags = {
    Name        = "packer-builder-${var.ami_prefix}"
    Environment = var.environment
    Purpose     = "ami-build"
  }
  
  # AMI Sharing (optional - uncomment to share with other accounts)
  # ami_users = var.ami_users
}

# -----------------------------------------------------------------------------
# Build Configuration
# -----------------------------------------------------------------------------
build {
  name    = "golden-ami"
  sources = ["source.amazon-ebs.golden"]
  
  # -----------------------------------------------------------------------------
  # Provisioner: Shell - Pre-Ansible Setup
  # -----------------------------------------------------------------------------
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "sudo cloud-init status --wait",
      "echo 'Updating system packages...'",
      "sudo yum update -y",
      "echo 'Installing Python 3 and pip for Ansible...'",
      "sudo yum install -y python3 python3-pip",
      "echo 'Pre-Ansible setup complete.'"
    ]
  }
  
  # -----------------------------------------------------------------------------
  # Provisioner: Ansible - Main Configuration
  # -----------------------------------------------------------------------------
  provisioner "ansible" {
    playbook_file = "../ansible/playbooks/golden-image.yml"
    user          = "ec2-user"
    use_proxy     = false
    
    # Extra variables passed to Ansible
    extra_arguments = [
      "--extra-vars", "ami_name=${local.ami_name}",
      "--extra-vars", "ami_version=${var.ami_version}",
      "--extra-vars", "environment=${var.environment}",
      "-vv"  # Verbosity level (remove for quieter output)
    ]
    
    # Environment variables for Ansible
    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_SSH_ARGS='-o ForwardAgent=yes -o ControlMaster=auto -o ControlPersist=60s'",
      "ANSIBLE_NOCOLOR=False"
    ]
  }
  
  # -----------------------------------------------------------------------------
  # Provisioner: Shell - Cleanup
  # -----------------------------------------------------------------------------
  provisioner "shell" {
    inline = [
      "echo 'Cleaning up temporary files...'",
      "sudo yum clean all",
      "sudo rm -rf /var/cache/yum",
      "sudo rm -rf /tmp/*",
      "sudo rm -rf /var/tmp/*",
      "sudo rm -f /root/.bash_history",
      "rm -f ~/.bash_history",
      "echo 'Removing SSH host keys (will regenerate on first boot)...'",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "echo 'Cleanup complete. AMI is ready for snapshot.'"
    ]
  }
  
  # -----------------------------------------------------------------------------
  # Post-Processor: Manifest
  # -----------------------------------------------------------------------------
  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
    custom_data = {
      ami_name    = local.ami_name
      ami_version = var.ami_version
      build_date  = timestamp()
    }
  }
}
