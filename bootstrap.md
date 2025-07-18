# AWS Terraform Bootstrap with GitHub OIDC

This guide walks you through setting up AWS infrastructure using Terraform with GitHub Actions OIDC authentication, eliminating the need for long-lived AWS access keys.

## 📁 Repository Structure

```
your-terraform-repo/
├── bootstrap/
│   ├── main.tf
│   ├── terraform.tfvars
│   └── backend.tf (created later)
├── .github/
│   └── workflows/
│       └── terraform.yml
├── main.tf (your actual infrastructure)
└── README.md
```

## 🚀 Step 1: Create the Module Repository (Optional)

If you want to publish this as a reusable module:

1. Create a new GitHub repository (e.g., `terraform-aws-bootstrap`)
2. Add the module files from above
3. Tag a release: `git tag v1.0.0 && git push --tags`

## 🛠️ Step 2: Bootstrap Directory Setup

### Create `bootstrap/main.tf`

```hcl
# bootstrap/main.tf
module "bootstrap" {
  source = "github.com/your-org/terraform-aws-bootstrap?ref=v1.0.0"
  # Or use local path during development: source = "../path/to/module"

  github_org     = var.github_org
  github_repo    = var.github_repo
  bucket_name    = var.bucket_name
  aws_region     = var.aws_region
  
  github_environments = var.github_environments

  # Optional: Add custom IAM permissions
  additional_iam_policies = [
    {
      Effect = "Allow"
      Action = [
        "ec2:*",
        "iam:*",
        "lambda:*",
        "logs:*",
        "rds:*"
      ]
      Resource = ["*"]
    }
  ]

  tags = {
    Project     = "MyProject"
    Team        = "DevOps"
    CostCenter  = "Engineering"
  }
}

# Variable declarations
variable "github_org" {
  description = "GitHub organization name"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket name for Terraform state"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "github_environments" {
  description = "List of GitHub environments to trust"
  type        = list(string)
  default     = ["production"]
}

# Outputs
output "role_arn" {
  value = module.bootstrap.github_actions_role_arn
}

output "bucket_name" {
  value = module.bootstrap.s3_bucket_name
}

output "backend_config" {
  value = module.bootstrap.backend_config
}
```

### Create `bootstrap/terraform.tfvars`

```hcl
# bootstrap/terraform.tfvars
github_org     = "your-github-org"
github_repo    = "your-repo-name"
bucket_name    = "your-unique-terraform-state-bucket-2025"  # Must be globally unique
aws_region     = "us-east-1"

github_environments = [
  "production",
  "staging"
]
```

## 🔑 Step 3: Initial Bootstrap (Using Temp IAM User)

### Prerequisites
- AWS account with a temporary IAM user
- AWS credentials added to GitHub repository secrets
- Terraform installed locally

### Execute Bootstrap

```bash
# 1. Clone your repository
git clone https://github.com/your-org/your-repo.git
cd your-repo

# 2. Set up AWS credentials for temp user
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="us-east-1"

# 3. Run bootstrap
cd bootstrap/
terraform init
terraform plan
terraform apply

# 4. Save important outputs
terraform output role_arn
terraform output bucket_name
terraform output backend_config
```

### Example Output
```
Outputs:

backend_config = {
  "bucket" = "your-unique-terraform-state-bucket-2025"
  "dynamodb_table" = "your-unique-terraform-state-bucket-2025-locks"
  "encrypt" = true
  "key" = "terraform.tfstate"
  "region" = "us-east-1"
}
role_arn = "arn:aws:iam::123456789012:role/github-actions-your-repo"
```

## 📦 Step 4: Migrate State to S3

```bash
# Still in bootstrap/ directory

# 1. Create backend configuration
cat > backend.tf << 'EOF'
terraform {
  backend "s3" {
    bucket         = "your-unique-terraform-state-bucket-2025"
    key            = "bootstrap/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "your-unique-terraform-state-bucket-2025-locks"
    encrypt        = true
  }
}
EOF

# 2. Re-initialize with backend migration
terraform init -migrate-state

# When prompted "Do you want to copy existing state to the new backend?", type: yes

# 3. Verify state is in S3
aws s3 ls s3://your-unique-terraform-state-bucket-2025/bootstrap/

# 4. Clean up local state file
rm terraform.tfstate*
```

## 🏗️ Step 5: Setup Main Infrastructure

### Create `main.tf` (root directory)

```hcl
# main.tf
terraform {
  required_version = ">= 1.0"
  
  backend "s3" {
    bucket         = "your-unique-terraform-state-bucket-2025"
    key            = "main/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "your-unique-terraform-state-bucket-2025-locks"
    encrypt        = true
  }
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Your infrastructure resources go here
resource "aws_instance" "example" {
  ami           = "ami-0c02fb55956c7d316"  # Amazon Linux 2
  instance_type = "t3.micro"

  tags = {
    Name = "Example Instance"
  }
}
```

## ⚙️ Step 6: GitHub Actions Setup

### Create GitHub Environments

1. Go to your repository → Settings → Environments
2. Create environments: `production`, `staging` (match your `github_environments`)
3. Add protection rules as needed

### Create `.github/workflows/terraform.yml`

```yaml
name: Terraform

on:
  push:
    branches: [main]
    paths-ignore:
      - 'bootstrap/**'
  pull_request:
    branches: [main]
    paths-ignore:
      - 'bootstrap/**'

permissions:
  id-token: write
  contents: read
  pull-requests: write

jobs:
  terraform:
    runs-on: ubuntu-latest
    environment: production  # Must match github_environments
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4

    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        role-to-assume: ${{ vars.AWS_ROLE_ARN }}
        aws-region: us-east-1

    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v3
      with:
        terraform_version: 1.6.0

    - name: Terraform Format
      run: terraform fmt -check

    - name: Terraform Init
      run: terraform init

    - name: Terraform Validate
      run: terraform validate

    - name: Terraform Plan
      run: terraform plan -no-color
      continue-on-error: true

    - name: Terraform Apply
      if: github.ref == 'refs/heads/main' && github.event_name == 'push'
      run: terraform apply -auto-approve
```

### Add Repository Variables

Go to Settings → Secrets and variables → Actions → Variables:

- **AWS_ROLE_ARN**: `arn:aws:iam::123456789012:role/github-actions-your-repo`

## 🧹 Step 7: Clean Up Temp User

1. **Test the workflow**: Push a change and verify GitHub Actions can assume the OIDC role
2. **Remove temp user secrets**: Delete `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` from GitHub
3. **Delete temp IAM user**: Remove the user from AWS Console
4. **Revoke local credentials**: Remove from your local environment

```bash
# Test that OIDC is working
git add .
git commit -m "Setup OIDC authentication"
git push origin main

# Watch the Actions tab to ensure the workflow succeeds
```

## 🔒 Security Best Practices

### OIDC Trust Conditions
The module configures trust to only allow:
- Your specific GitHub organization and repository
- Specific GitHub environments you define
- Only the `sts.amazonaws.com` audience

### S3 Security
- ✅ Versioning enabled
- ✅ Encryption at rest
- ✅ Public access blocked
- ✅ Bucket policies restrictive

### IAM Permissions
- ✅ Least privilege access
- ✅ No long-lived credentials
- ✅ Scoped to specific resources

## 🐛 Troubleshooting

### Common Issues

**OIDC Authentication Fails**
```
Error: could not assume role with web identity
```
- Verify GitHub environment names match `github_environments`
- Check repository and organization names are correct
- Ensure workflow runs in the correct environment

**S3 Access Denied**
```
Error: AccessDenied: Access Denied
```
- Verify IAM role has S3 permissions
- Check bucket name is correct in backend config
- Ensure DynamoDB table exists

**State Locking Issues**
```
Error: Error acquiring the state lock
```
- Check DynamoDB table permissions
- Verify table name matches in backend config
- Manual unlock: `terraform force-unlock LOCK_ID`

### Validation Commands

```bash
# Test AWS access
aws sts get-caller-identity

# Validate Terraform
terraform validate

# Check state backend
terraform state list

# Verify S3 bucket
aws s3 ls s3://your-bucket-name/
```

## 🔄 Updating the Bootstrap

If you need to modify the bootstrap infrastructure:

```bash
cd bootstrap/
# Make changes to terraform.tfvars or add resources
terraform plan
terraform apply
```

The bootstrap state is separate from your main infrastructure, so you can safely modify it without affecting your production resources.

## 📚 Next Steps

1. **Add more environments**: Create `development`, `staging` environments
2. **Implement branch protection**: Require PR reviews for main branch
3. **Add policy automation**: Use tools like Checkov or tfsec in CI
4. **Monitor costs**: Set up AWS Cost Explorer alerts
5. **Backup strategy**: Consider cross-region S3 replication for state files

## 🎯 Module Customization

You can extend the module by adding:
- Custom IAM policies via `additional_iam_policies`
- Additional tags via `tags` variable
- Multiple repositories by creating multiple instances
- Cross-account access by modifying trust policies

This bootstrap approach gives you a secure, scalable foundation for managing AWS infrastructure with Terraform and GitHub Actions!
