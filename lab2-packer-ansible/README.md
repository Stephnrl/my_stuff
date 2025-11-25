# Lab 2: Building Golden AMIs with Packer + Ansible

## Overview

In this lab, you'll learn how to create a **Golden AMI** (Amazon Machine Image) using Packer with Ansible as the provisioner. This is a foundational pattern in immutable infrastructure—baking configuration into images rather than configuring instances at boot time.

## Learning Objectives

By the end of this lab, you will be able to:

- Write Packer HCL configuration files
- Use Ansible as a Packer provisioner
- Build hardened, repeatable AMIs
- Understand the "bake vs fry" infrastructure pattern
- Tag and version AMIs for lifecycle management

## Prerequisites

- Completed Lab 1 (Ansible Fundamentals)
- Your Ansible virtual environment activated (`activate-ansible`)
- AWS CLI configured with appropriate credentials
- Packer installed (we'll verify this)

## Lab Duration

Approximately 60-90 minutes

---

## Part 1: Environment Setup (10 minutes)

### 1.1 Activate Your Environment

```bash
# Activate your Ansible environment
source ~/activate-ansible.sh

# Verify Ansible is available
ansible --version
```

### 1.2 Verify Packer Installation

```bash
# Check Packer version
packer version

# Expected output: Packer v1.10.x or higher
```

### 1.3 Verify AWS Credentials

```bash
# Confirm you're in the correct region
aws sts get-caller-identity
aws configure get region

# Should return: us-gov-west-1
```

### 1.4 Clone the Lab Files

```bash
# Navigate to your home directory
cd ~

# Clone or copy the lab files
cp -r /opt/labs/lab2-packer-ansible ~/lab2
cd ~/lab2

# Review the structure
tree .
```

---

## Part 2: Understanding the Lab Structure (10 minutes)

### 2.1 Directory Layout

```
lab2-packer-ansible/
├── packer/
│   ├── golden-ami.pkr.hcl      # Main Packer configuration
│   ├── variables.pkr.hcl        # Variable definitions
│   └── variables.auto.pkrvars.hcl # Variable values
├── ansible/
│   ├── playbooks/
│   │   └── golden-image.yml     # Main provisioning playbook
│   ├── roles/
│   │   ├── base/                # Base OS configuration
│   │   ├── security/            # Security hardening
│   │   └── monitoring/          # Monitoring agents
│   └── inventory/
│       └── localhost.yml        # Local inventory for Packer
└── README.md
```

### 2.2 The "Bake vs Fry" Concept

| Approach | Description | Pros | Cons |
|----------|-------------|------|------|
| **Bake** (Packer) | Configuration built into AMI | Fast boot, immutable, consistent | Longer build time, more AMIs to manage |
| **Fry** (User Data) | Configuration at boot time | Flexible, fewer AMIs | Slower boot, potential drift |

**Best Practice**: Bake base configuration + security, fry application-specific config.

---

## Part 3: Packer Configuration Deep Dive (15 minutes)

### 3.1 Examine the Packer Configuration

Open `packer/golden-ami.pkr.hcl` and review each section:

```bash
cat packer/golden-ami.pkr.hcl
```

**Key sections to understand:**

1. **packer block** - Required plugins
2. **source block** - Where and how to build (AWS, instance type, base AMI)
3. **build block** - What to run (provisioners)

### 3.2 Understanding the Source AMI Filter

```hcl
source_ami_filter {
  filters = {
    name                = "amzn2-ami-hvm-*-x86_64-gp2"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  owners      = ["amazon"]
  most_recent = true
}
```

This dynamically finds the latest Amazon Linux 2 AMI rather than hardcoding an AMI ID.

### 3.3 Examine Variables

```bash
cat packer/variables.pkr.hcl
cat packer/variables.auto.pkrvars.hcl
```

**Exercise**: Modify `variables.auto.pkrvars.hcl` to add your username to the AMI name:

```hcl
ami_prefix = "golden-ami-<YOUR_USERNAME>"
```

---

## Part 4: Ansible Provisioner Configuration (15 minutes)

### 4.1 Review the Golden Image Playbook

```bash
cat ansible/playbooks/golden-image.yml
```

This playbook runs **inside the temporary Packer instance** to configure it before the AMI is created.

### 4.2 Examine the Roles

**Base Role** - Core OS configuration:
```bash
cat ansible/roles/base/tasks/main.yml
```

**Security Role** - Hardening:
```bash
cat ansible/roles/security/tasks/main.yml
```

**Monitoring Role** - CloudWatch agent setup:
```bash
cat ansible/roles/monitoring/tasks/main.yml
```

### 4.3 Understanding the Packer-Ansible Connection

In `golden-ami.pkr.hcl`, the Ansible provisioner:

```hcl
provisioner "ansible" {
  playbook_file = "../ansible/playbooks/golden-image.yml"
  user          = "ec2-user"
  use_proxy     = false
  ansible_env_vars = [
    "ANSIBLE_HOST_KEY_CHECKING=False"
  ]
}
```

Packer automatically:
1. Launches a temporary EC2 instance
2. Waits for SSH to be available
3. Runs Ansible against that instance
4. Creates an AMI from the configured instance
5. Terminates the temporary instance

---

## Part 5: Building Your First Golden AMI (20 minutes)

### 5.1 Validate the Packer Configuration

```bash
cd ~/lab2/packer

# Initialize Packer (downloads required plugins)
packer init .

# Validate syntax
packer validate .

# Expected output: The configuration is valid.
```

### 5.2 Preview the Build (Dry Run)

```bash
# See what Packer will do without actually building
packer inspect golden-ami.pkr.hcl
```

### 5.3 Build the AMI

```bash
# Run the build with detailed output
packer build -color=true -timestamp-ui .
```

**What you'll see:**

1. `amazon-ebs.golden: Creating temporary security group...`
2. `amazon-ebs.golden: Launching a source AWS instance...`
3. `amazon-ebs.golden: Waiting for SSH to become available...`
4. `amazon-ebs.golden: Provisioning with Ansible...`
5. `amazon-ebs.golden: Stopping the source instance...`
6. `amazon-ebs.golden: Creating AMI...`
7. `amazon-ebs.golden: AMI: ami-xxxxxxxxxxxxxxxxx`

**Note**: This process takes approximately 8-12 minutes.

### 5.4 Verify Your AMI

```bash
# List your AMIs
aws ec2 describe-images \
  --owners self \
  --query 'Images[*].[ImageId,Name,CreationDate]' \
  --output table

# Get detailed info about your new AMI
aws ec2 describe-images \
  --owners self \
  --filters "Name=name,Values=golden-ami-*" \
  --query 'Images | sort_by(@, &CreationDate) | [-1]'
```

---

## Part 6: Customization Exercise (20 minutes)

Now that you've built a basic Golden AMI, let's customize it.

### 6.1 Add a New Role: Application Prerequisites

Create a new role that installs common application dependencies:

```bash
# Create role structure
mkdir -p ~/lab2/ansible/roles/app_prereqs/{tasks,files,templates}

# Create the tasks file
cat > ~/lab2/ansible/roles/app_prereqs/tasks/main.yml << 'EOF'
---
- name: Install application prerequisites
  ansible.builtin.yum:
    name:
      - git
      - docker
      - jq
      - tree
    state: present

- name: Start and enable Docker
  ansible.builtin.systemd:
    name: docker
    state: started
    enabled: yes

- name: Create application directories
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    mode: '0755'
  loop:
    - /opt/app
    - /opt/app/logs
    - /opt/app/config

- name: Add MOTD banner
  ansible.builtin.template:
    src: motd.j2
    dest: /etc/motd
    mode: '0644'
EOF
```

### 6.2 Create the MOTD Template

```bash
cat > ~/lab2/ansible/roles/app_prereqs/templates/motd.j2 << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║   🏗️  Golden AMI - Built with Packer + Ansible               ║
║                                                               ║
║   Build Date: {{ ansible_date_time.iso8601 }}                 ║
║   Base OS:    {{ ansible_distribution }} {{ ansible_distribution_version }}
║   Region:     us-gov-west-1                                   ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
```

### 6.3 Update the Playbook

Edit `ansible/playbooks/golden-image.yml` to include your new role:

```yaml
roles:
  - base
  - security
  - monitoring
  - app_prereqs    # Add this line
```

### 6.4 Rebuild the AMI

```bash
cd ~/lab2/packer
packer build -color=true -timestamp-ui .
```

---

## Part 7: Testing Your AMI (Optional, 10 minutes)

### 7.1 Launch a Test Instance

```bash
# Get your latest AMI ID
AMI_ID=$(aws ec2 describe-images \
  --owners self \
  --filters "Name=name,Values=golden-ami-*" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
  --output text)

echo "Launching instance from AMI: $AMI_ID"

# Launch a test instance (use your lab's subnet and security group)
aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t3.micro \
  --key-name lab-key \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=golden-ami-test},{Key=Environment,Value=lab}]' \
  --query 'Instances[0].InstanceId' \
  --output text
```

### 7.2 Verify the Configuration

SSH into your test instance and verify:

```bash
# Check the MOTD displayed on login
# Verify installed packages
which git docker jq

# Check services
systemctl status docker
systemctl status amazon-cloudwatch-agent

# Check security hardening
cat /etc/ssh/sshd_config | grep PermitRootLogin
```

### 7.3 Clean Up Test Instance

```bash
# Terminate the test instance when done
aws ec2 terminate-instances --instance-ids <INSTANCE_ID>
```

---

## Lab Challenges (Extra Credit)

### Challenge 1: Add AMI Encryption
Modify the Packer configuration to create an encrypted AMI using a KMS key.

### Challenge 2: Multi-Region AMI
Add a `post-processor` to copy the AMI to `us-gov-east-1`.

### Challenge 3: AMI Validation
Add a `shell` provisioner that runs validation tests before the AMI is created.

### Challenge 4: Ansible Vault Integration
Store sensitive variables (like API keys) in an Ansible Vault and integrate with Packer.

---

## Cleanup

When finished with the lab:

```bash
# Deregister AMIs you no longer need
aws ec2 deregister-image --image-id ami-xxxxxxxxx

# Delete associated snapshots
aws ec2 delete-snapshot --snapshot-id snap-xxxxxxxxx
```

---

## Key Takeaways

1. **Packer + Ansible** is a powerful combination for building immutable infrastructure
2. **Golden AMIs** provide consistency, security, and faster deployment
3. **Source AMI filters** ensure you always build on the latest base image
4. **Tagging** is critical for AMI lifecycle management
5. **Test your AMIs** before promoting to production

---

## Next Lab Preview

In **Lab 3: Terraform + Custom AMI**, you'll use the Golden AMI you created here to deploy infrastructure with Terraform, including:

- VPCs and networking
- Auto Scaling Groups
- Load Balancers
- Using `data` sources to find your AMI

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `VPCIdNotSpecified` | Add `vpc_id` and `subnet_id` to Packer config |
| SSH timeout | Check security group allows SSH from Packer build host |
| Ansible failures | Run Packer with `PACKER_LOG=1` for detailed output |
| AMI not found | Verify `owners` in source_ami_filter matches GovCloud |

## Resources

- [Packer Documentation](https://developer.hashicorp.com/packer/docs)
- [Packer AWS Builder](https://developer.hashicorp.com/packer/plugins/builders/amazon)
- [Ansible Packer Provisioner](https://developer.hashicorp.com/packer/docs/provisioners/ansible)
