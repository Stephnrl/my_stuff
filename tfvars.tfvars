#==============================================================================
# prod.tfvars - Production Environment Configuration
#==============================================================================

# Basic Project Settings
project_name = "mycompany-platform"
environment  = "prod"
aws_region   = "us-east-1"

# GitHub Configuration
github_owner           = "mycompany"
github_repository_name = "mycompany/infrastructure-repo"

github_repositories = [
  "mycompany/infrastructure-repo",
  "mycompany/api-backend",
  "mycompany/frontend-app",
  "mycompany/mobile-app"
]

# GitHub Environment Management
manage_github_environments = true

# Production Approval Settings - STRICT
github_reviewers = {
  users = [
    "devops-lead",
    "platform-engineer", 
    "security-lead",
    "your-github-username"
  ]
  teams = [
    "devops-team",
    "platform-team", 
    "security-team"
  ]
}

github_protected_branches    = true   # Only main branch can deploy
github_custom_branch_policies = false
github_wait_timer_minutes    = 10     # 10 minute wait before prod deployment

# AWS Security Settings - PRODUCTION
force_destroy_state_bucket              = false  # Protect production state
enable_state_lifecycle                  = true
state_version_expiration_days           = 365    # Keep versions for 1 year
enable_dynamodb_point_in_time_recovery  = true   # Enable backups
terraform_state_key_prefix              = "infrastructure"

# OIDC Provider Settings
create_github_oidc_provider = true

# IAM Policies - More restrictive for production
additional_terraform_policies = [
  "arn:aws:iam::aws:policy/PowerUserAccess"
  # Add more specific policies as needed:
  # "arn:aws:iam::123456789012:policy/CustomTerraformPolicy"
]

# Production Secrets
additional_github_secrets = {
  # Monitoring & Alerting
  "DATADOG_API_KEY"           = "your-prod-datadog-api-key"
  "DATADOG_APP_KEY"           = "your-prod-datadog-app-key"
  "NEW_RELIC_LICENSE_KEY"     = "your-newrelic-license-key"
  "PAGERDUTY_INTEGRATION_KEY" = "your-pagerduty-key"
  
  # Communication
  "SLACK_WEBHOOK_URL"         = "https://hooks.slack.com/services/PROD/ALERTS/WEBHOOK"
  "SLACK_CHANNEL"             = "#prod-alerts"
  
  # External Services
  "PROD_DATABASE_URL"         = "postgresql://user:pass@prod-db.company.com:5432/db"
  "REDIS_URL"                 = "redis://prod-redis.company.com:6379"
  "ELASTICSEARCH_URL"         = "https://prod-es.company.com:9200"
  
  # API Keys
  "STRIPE_SECRET_KEY"         = "sk_live_your_stripe_key"
  "SENDGRID_API_KEY"          = "SG.your_sendgrid_key"
  "AWS_SES_REGION"            = "us-east-1"
  
  # Custom Application Settings
  "APP_ENV"                   = "production"
  "LOG_LEVEL"                 = "info"
  "FEATURE_FLAG_SERVICE"      = "https://flags.company.com"
  "CDN_BASE_URL"              = "https://cdn.company.com"
}

# Resource Tagging - Production
tags = {
  Environment   = "production"
  Project       = "platform"
  Owner         = "devops-team"
  CostCenter    = "engineering"
  Compliance    = "required"
  Backup        = "required"
  Monitoring    = "critical"
  BusinessUnit  = "platform"
}

#==============================================================================
# nonprod.tfvars - Non-Production Environment Configuration  
#==============================================================================

# Basic Project Settings
project_name = "mycompany-platform"
environment  = "nonprod"
aws_region   = "us-west-2"  # Different region for cost optimization

# GitHub Configuration (same as prod)
github_owner           = "mycompany"
github_repository_name = "mycompany/infrastructure-repo"

github_repositories = [
  "mycompany/infrastructure-repo",
  "mycompany/api-backend",
  "mycompany/frontend-app",
  "mycompany/mobile-app"
]

# GitHub Environment Management
manage_github_environments = true

# Non-Production Settings - RELAXED
github_reviewers = {
  users = []  # No approval required for nonprod
  teams = []
}

github_protected_branches    = false  # Allow develop and main branches
github_custom_branch_policies = false
github_wait_timer_minutes    = 0      # No wait timer

# AWS Settings - COST OPTIMIZED
force_destroy_state_bucket              = true   # Allow cleanup
enable_state_lifecycle                  = true
state_version_expiration_days           = 90     # Shorter retention
enable_dynamodb_point_in_time_recovery  = false  # Cost savings
terraform_state_key_prefix              = "infrastructure"

# OIDC Provider Settings - Reuse from prod
create_github_oidc_provider       = false
existing_github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"

# IAM Policies - More permissive for development
additional_terraform_policies = [
  "arn:aws:iam::aws:policy/PowerUserAccess"
  # Could add broader permissions for experimentation
]

# Non-Production Secrets
additional_github_secrets = {
  # Monitoring & Alerting (dev/staging keys)
  "DATADOG_API_KEY"           = "your-nonprod-datadog-api-key"
  "NEW_RELIC_LICENSE_KEY"     = "your-dev-newrelic-license-key"
  
  # Communication
  "SLACK_WEBHOOK_URL"         = "https://hooks.slack.com/services/DEV/ALERTS/WEBHOOK"
  "SLACK_CHANNEL"             = "#dev-alerts"
  
  # External Services (staging/dev endpoints)
  "STAGING_DATABASE_URL"      = "postgresql://user:pass@staging-db.company.com:5432/db"
  "DEV_DATABASE_URL"          = "postgresql://user:pass@dev-db.company.com:5432/db"
  "REDIS_URL"                 = "redis://staging-redis.company.com:6379"
  "ELASTICSEARCH_URL"         = "https://staging-es.company.com:9200"
  
  # API Keys (test keys)
  "STRIPE_SECRET_KEY"         = "sk_test_your_stripe_test_key"
  "SENDGRID_API_KEY"          = "SG.your_test_sendgrid_key"
  "AWS_SES_REGION"            = "us-west-2"
  
  # Custom Application Settings
  "APP_ENV"                   = "staging"
  "LOG_LEVEL"                 = "debug"
  "FEATURE_FLAG_SERVICE"      = "https://flags-staging.company.com"
  "CDN_BASE_URL"              = "https://cdn-staging.company.com"
  
  # Development-specific
  "DEBUG_MODE"                = "true"
  "MOCK_EXTERNAL_APIS"        = "true"
}

# Resource Tagging - Non-Production
tags = {
  Environment   = "non-production"
  Project       = "platform"
  Owner         = "devops-team"
  CostCenter    = "engineering"
  Compliance    = "optional"
  Backup        = "optional"
  Monitoring    = "standard"
  BusinessUnit  = "platform"
}

#==============================================================================
# test.tfvars - Quick Testing Configuration
#==============================================================================

# Minimal settings for quick testing
project_name = "test-bootstrap"
environment  = "test"
aws_region   = "us-east-1"

# GitHub Settings
github_owner           = "your-org"
github_repository_name = "your-org/testing-repo"
github_repositories    = ["your-org/testing-repo"]

# Simple GitHub setup for testing
manage_github_environments = true
github_reviewers = {
  users = ["your-github-username"]
  teams = []
}
github_protected_branches = false
github_wait_timer_minutes = 0

# Test-friendly AWS settings
force_destroy_state_bucket              = true   # Easy cleanup
enable_state_lifecycle                  = false  # Simpler
state_version_expiration_days           = 30     # Short retention
enable_dynamodb_point_in_time_recovery  = false  # Cost savings

# Simple test secrets
additional_github_secrets = {
  "TEST_SECRET"     = "test-value"
  "API_ENDPOINT"    = "https://api-test.company.com"
  "DEBUG_MODE"      = "true"
}

# Test tags
tags = {
  Purpose     = "testing"
  Environment = "test"
  Owner       = "your-name"
}
