# Advanced Repository Tracking Methods
# File: tracking.tf (additional tracking approaches)

# Approach 2: Query Existing Repositories
# =======================================

# Data source to get all repositories in the organization
data "github_repositories" "all_managed_repos" {
  query = "org:${var.github_organization} topic:managed-by-platform"
  
  depends_on = [module.team_repositories]
}

# Create a comprehensive report of all managed repositories
resource "local_file" "managed_repositories_report" {
  filename = "${path.module}/outputs/managed-repositories-report.json"
  
  content = jsonencode({
    report_generated_at = timestamp()
    organization = var.github_organization
    query_used = "org:${var.github_organization} topic:managed-by-platform"
    
    summary = {
      total_managed_repos = length(data.github_repositories.all_managed_repos.names)
      repos_created_this_run = length(local.teams)
    }
    
    all_managed_repositories = [
      for repo_name in data.github_repositories.all_managed_repos.names : {
        name = repo_name
        full_name = data.github_repositories.all_managed_repos.full_names[index(data.github_repositories.all_managed_repos.names, repo_name)]
        created_by_this_run = contains([for k, v in local.teams : v.repository_name], repo_name)
      }
    ]
    
    repositories_created_this_run = {
      for team_name, team_config in local.teams : team_name => {
        repository_name = team_config.repository_name
        repository_url = module.team_repositories[team_name].repository_url
        team_leads = team_config.team_leads
        aws_account = team_config.aws_account_id
      }
    }
  })
  
  depends_on = [module.team_repositories, data.github_repositories.all_managed_repos]
}

# Approach 3: S3-Based Central Registry
# =====================================

# Upload repository registry to S3 for centralized tracking
resource "aws_s3_object" "repository_registry" {
  bucket = var.central_tracking_bucket
  key    = "platform/repository-registry/${formatdate("YYYY/MM", timestamp())}/registry-${formatdate("YYYY-MM-DD-hhmm", timestamp())}.json"
  
  content = jsonencode({
    registry_version = "1.0"
    generated_at = timestamp()
    generated_by = "platform-team-landing-zone"
    terraform_run_id = var.terraform_run_id # Pass this as a variable
    
    platform_metadata = {
      terraform_version = "1.0+"
      github_organization = var.github_organization
      aws_region = var.aws_region
      deployment_environment = var.deployment_environment
    }
    
    repositories = {
      for team_name, team_config in local.teams : team_name => {
        # Repository information
        repository = {
          name = team_config.repository_name
          full_name = module.team_repositories[team_name].repository_full_name
          url = module.team_repositories[team_name].repository_url
          ssh_clone_url = module.team_repositories[team_name].repository_ssh_clone_url
          id = module.team_repositories[team_name].repository_id
          default_branch = module.team_repositories[team_name].default_branch
        }
        
        # Team information
        team = {
          name = team_name
          leads = team_config.team_leads
          contact_email = team_config.contact_email
          cost_center = team_config.cost_center
        }
        
        # AWS integration
        aws = {
          account_id = team_config.aws_account_id
          environments = team_config.environments
          oidc_roles = {
            for env in team_config.environments : env => 
            "arn:aws:iam::${team_config.aws_account_id}:role/team-${team_name}-${env}-role"
          }
        }
        
        # Governance
        governance = {
          created_date = team_config.created_date
          last_updated = timestamp()
          status = "active"
          compliance_tags = {
            managed_by = "platform-team"
            auto_created = true
            security_reviewed = true
          }
        }
        
        # GitHub configuration
        github_config = {
          visibility = "private"
          branch_protection_enabled = true
          environments = keys(module.team_repositories[team_name].environments)
          team_access = module.team_repositories[team_name].team_access
        }
      }
    }
  })
  
  content_type = "application/json"
  
  tags = {
    Purpose = "RepositoryTracking"
    GeneratedBy = "TerraformLandingZone"
    Date = formatdate("YYYY-MM-DD", timestamp())
  }
  
  depends_on = [module.team_repositories]
}

# Create a "latest" pointer for easy access
resource "aws_s3_object" "repository_registry_latest" {
  bucket = var.central_tracking_bucket
  key    = "platform/repository-registry/latest.json"
  
  content = aws_s3_object.repository_registry.content
  content_type = "application/json"
  
  tags = {
    Purpose = "RepositoryTrackingLatest"
    GeneratedBy = "TerraformLandingZone"
    Date = formatdate("YYYY-MM-DD", timestamp())
  }
}

# Approach 4: DynamoDB Tracking Table
# ===================================

# DynamoDB table for real-time repository tracking
resource "aws_dynamodb_table_item" "repository_tracking" {
  for_each   = local.teams
  table_name = var.repository_tracking_table
  hash_key   = "repository_id"
  
  item = jsonencode({
    repository_id = {
      S = module.team_repositories[each.key].repository_id
    }
    team_name = {
      S = each.key
    }
    repository_name = {
      S = each.value.repository_name
    }
    repository_url = {
      S = module.team_repositories[each.key].repository_url
    }
    full_name = {
      S = module.team_repositories[each.key].repository_full_name
    }
    aws_account_id = {
      S = each.value.aws_account_id
    }
    team_leads = {
      SS = each.value.team_leads
    }
    environments = {
      SS = each.value.environments
    }
    cost_center = {
      S = each.value.cost_center
    }
    contact_email = {
      S = each.value.contact_email
    }
    created_date = {
      S = each.value.created_date
    }
    last_updated = {
      S = timestamp()
    }
    status = {
      S = "active"
    }
    managed_by = {
      S = "platform-team"
    }
    terraform_managed = {
      BOOL = true
    }
  })
  
  depends_on = [module.team_repositories]
}

# Approach 5: Workspace-Based Tracking
# ====================================

# Create a workspace summary file
resource "local_file" "workspace_summary" {
  filename = "${path.module}/outputs/workspace-${terraform.workspace}-summary.json"
  
  content = jsonencode({
    workspace = terraform.workspace
    generated_at = timestamp()
    
    workspace_metadata = {
      terraform_version = "1.0+"
      provider_versions = {
        github = "~> 6.0"
        aws = "~> 5.0"
      }
    }
    
    repositories_in_workspace = {
      for team_name, team_config in local.teams : team_name => {
        repository_name = team_config.repository_name
        status = "created"
        terraform_address = "module.team_repositories[\"${team_name}\"]"
        github_url = module.team_repositories[team_name].repository_url
      }
    }
    
    summary = {
      total_repos = length(local.teams)
      workspace = terraform.workspace
      all_repos_created = true
    }
  })
  
  depends_on = [module.team_repositories]
}

# Variables for advanced tracking
variable "central_tracking_bucket" {
  description = "S3 bucket for central repository tracking"
  type        = string
  default     = null
}

variable "repository_tracking_table" {
  description = "DynamoDB table for repository tracking"
  type        = string
  default     = null
}

variable "terraform_run_id" {
  description = "Unique identifier for this Terraform run"
  type        = string
  default     = null
}

variable "deployment_environment" {
  description = "Environment where this landing zone is deployed"
  type        = string
  default     = "production"
}

# Outputs for tracking
output "tracking_information" {
  description = "Information about repository tracking"
  value = {
    local_files = {
      inventory_json = "${path.module}/outputs/repository-inventory.json"
      inventory_csv = "${path.module}/outputs/repository-inventory.csv"
      managed_repos_report = "${path.module}/outputs/managed-repositories-report.json"
      workspace_summary = "${path.module}/outputs/workspace-${terraform.workspace}-summary.json"
    }
    
    s3_tracking = var.central_tracking_bucket != null ? {
      registry_key = aws_s3_object.repository_registry.key
      latest_key = aws_s3_object.repository_registry_latest.key
      bucket = var.central_tracking_bucket
    } : null
    
    dynamodb_tracking = var.repository_tracking_table != null ? {
      table_name = var.repository_tracking_table
      items_created = length(local.teams)
    } : null
    
    github_query = {
      organization = var.github_organization
      managed_repos_query = "org:${var.github_organization} topic:managed-by-platform"
      total_managed_repos = length(data.github_repositories.all_managed_repos.names)
    }
  }
}
