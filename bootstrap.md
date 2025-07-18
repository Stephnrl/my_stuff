# AWS Terraform Bootstrap with GitHub OIDC

This guide walks you through setting up AWS infrastructure using Terraform with GitHub Actions OIDC authentication. The bootstrap process uses AWS IAM Identity Center (SSO) for secure, temporary credentials - no long-lived keys needed anywhere!

## ✨ Why Use SSO for Bootstrap?

✅ **No temporary IAM users**: No need to create and manage temporary accounts  
✅ **Short-lived credentials**: SSO tokens automatically expire (typically 1-12 hours)  
✅ **MFA enforcement**: Your existing SSO MFA policies apply  
✅ **Audit trail**: All actions are logged under your identity  
✅ **Zero credential management**: No keys to rotate or secure  
✅ **Consistent access**: Same login method for console and CLI

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
bucket_name    = "my-terraform-state"  # Random 6-char suffix will be added automatically
aws_region     = "us-east-1"

github_environments = [
  "production",
  "staging"
]
```

## 🔑 Step 3: Initial Bootstrap (Using AWS SSO)

### Prerequisites
- AWS account with IAM Identity Center (SSO) access
- Administrative permissions or sufficient permissions to create IAM roles, S3 buckets, etc.
- AWS CLI v2 installed
- Terraform installed locally

### Setup AWS SSO Profile

```bash
# 1. Configure AWS SSO (if not already done)
aws configure sso

# Follow the prompts:
# SSO session name: my-sso
# SSO start URL: https://my-org.awsapps.com/start
# SSO region: us-east-1
# Registration scopes: sso:account:access
# Account ID: 123456789012
# Role name: AdministratorAccess (or your role)
# CLI default client Region: us-east-1
# CLI default output format: json
# CLI profile name: my-admin-profile

# 2. Test SSO login
aws sso login --profile my-admin-profile

# 3. Verify access
aws sts get-caller-identity --profile my-admin-profile
```

### Alternative: Using Shared SSO Configuration

If your team already has a shared SSO configuration, you can add it to `~/.aws/config`:

```ini
[profile my-admin-profile]
sso_session = my-org-sso
sso_account_id = 123456789012
sso_role_name = AdministratorAccess
region = us-east-1
output = json

[sso-session my-org-sso]
sso_start_url = https://my-org.awsapps.com/start
sso_region = us-east-1
sso_registration_scopes = sso:account:access
```

### Execute Bootstrap

```bash
# 1. Clone your repository
git clone https://github.com/your-org/your-repo.git
cd your-repo

# 2. Set AWS profile for this session
export AWS_PROFILE=my-admin-profile

# Optional: Verify your identity
aws sts get-caller-identity

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
  "bucket" = "my-terraform-state-a1b2c3"
  "dynamodb_table" = "my-terraform-state-a1b2c3-locks"
  "encrypt" = true
  "key" = "terraform.tfstate"
  "region" = "us-east-1"
}
role_arn = "arn:aws:iam::123456789012:role/github-actions-your-repo"
s3_bucket_name = "my-terraform-state-a1b2c3"
s3_bucket_suffix = "a1b2c3"
```

## 📦 Step 4: Migrate State to S3

```bash
# Still in bootstrap/ directory
# Make sure your SSO session is still active
aws sts get-caller-identity --profile my-admin-profile

# If session expired, renew it
# aws sso login --profile my-admin-profile

# 1. Get the actual bucket name with suffix
BUCKET_NAME=$(terraform output -raw s3_bucket_name)
DYNAMO_TABLE=$(terraform output -raw dynamodb_table_name)

echo "Bucket: $BUCKET_NAME"
echo "DynamoDB Table: $DYNAMO_TABLE"

# 2. Create backend configuration with actual names
cat > backend.tf << EOF
terraform {
  backend "s3" {
    bucket         = "$BUCKET_NAME"
    key            = "bootstrap/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "$DYNAMO_TABLE"
    encrypt        = true
  }
}
EOF

# 3. Re-initialize with backend migration
terraform init -migrate-state

# When prompted "Do you want to copy existing state to the new backend?", type: yes

# 4. Verify state is in S3
aws s3 ls s3://$BUCKET_NAME/bootstrap/

# 5. Clean up local state file
rm terraform.tfstate*
```

## 🏗️ Step 5: Setup Main Infrastructure

### Get Bootstrap Values

```bash
# From the bootstrap directory, get the values you need
cd bootstrap/
export BUCKET_NAME=$(terraform output -raw s3_bucket_name)
export DYNAMO_TABLE=$(terraform output -raw dynamodb_table_name)
export ROLE_ARN=$(terraform output -raw github_actions_role_arn)

echo "S3 Bucket: $BUCKET_NAME"
echo "DynamoDB Table: $DYNAMO_TABLE" 
echo "IAM Role ARN: $ROLE_ARN"

# Go back to root directory
cd ..
```

### Create `main.tf` (root directory)

```hcl
# main.tf
terraform {
  required_version = ">= 1.0"
  
  backend "s3" {
    # Update these values with outputs from your bootstrap
    bucket         = "my-terraform-state-a1b2c3"  # Use actual bucket name from bootstrap output
    key            = "main/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "my-terraform-state-a1b2c3-locks"  # Use actual table name from bootstrap output
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

## 🧹 Step 7: Verify and Clean Up

1. **Test the workflow**: Push a change and verify GitHub Actions can assume the OIDC role
2. **Verify SSO setup**: Ensure your regular development workflow uses SSO credentials
3. **Clean up local environment**: Remove any exported AWS environment variables

```bash
# Test that OIDC is working
git add .
git commit -m "Setup OIDC authentication"
git push origin main

# Watch the Actions tab to ensure the workflow succeeds

# Clean up any environment variables (if you set them)
unset AWS_PROFILE
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY

# For future local development, always use SSO
aws sso login --profile my-admin-profile
export AWS_PROFILE=my-admin-profile
```

### SSO Session Management

```bash
# Check current SSO session status
aws sts get-caller-identity --profile my-admin-profile

# If session expired, renew it
aws sso login --profile my-admin-profile

# List all SSO sessions
aws sso list-accounts --profile my-admin-profile

# For convenience, add to your shell profile (~/.bashrc, ~/.zshrc)
alias awslogin="aws sso login --profile my-admin-profile && export AWS_PROFILE=my-admin-profile"
```

## 🔒 Security Best Practices

### Bootstrap Security
- ✅ **No long-lived credentials**: Uses AWS SSO temporary credentials only
- ✅ **MFA enforcement**: SSO typically requires multi-factor authentication
- ✅ **Session-based access**: Credentials automatically expire
- ✅ **Centralized access control**: Managed through IAM Identity Center

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
- ✅ No long-lived credentials anywhere
- ✅ Scoped to specific resources

## 🐛 Troubleshooting

### Common Issues

**SSO Session Expired**
```
Error: The security token included in the request is invalid
```
- Run: `aws sso login --profile my-admin-profile`
- Verify: `aws sts get-caller-identity --profile my-admin-profile`
- Set profile: `export AWS_PROFILE=my-admin-profile`

**SSO Profile Not Found**
```
Error: The config profile (my-admin-profile) could not be found
```
- Reconfigure SSO: `aws configure sso`
- List profiles: `aws configure list-profiles`
- Check config: `cat ~/.aws/config`

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
# Test AWS SSO access
aws sts get-caller-identity --profile my-admin-profile

# Or if AWS_PROFILE is set
aws sts get-caller-identity

# Get bootstrap outputs (from bootstrap/ directory)
terraform output

# Get specific values
terraform output -raw s3_bucket_name
terraform output -raw github_actions_role_arn

# Validate Terraform
terraform validate

# Check state backend
terraform state list

# Verify S3 bucket
aws s3 ls s3://$(terraform output -raw s3_bucket_name)/
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
