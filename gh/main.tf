# GitHub Repository Module
# File: modules/github-repo/main.tf

terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

# Create the GitHub repository
resource "github_repository" "team_repo" {
  name        = var.repository_name
  description = var.repository_description
  visibility  = var.repository_visibility
  
  # Repository settings
  has_issues      = var.has_issues
  has_projects    = var.has_projects
  has_wiki        = var.has_wiki
  has_downloads   = var.has_downloads
  has_discussions = var.has_discussions
  
  # Security and merge settings
  allow_merge_commit     = var.allow_merge_commit
  allow_squash_merge     = var.allow_squash_merge
  allow_rebase_merge     = var.allow_rebase_merge
  delete_branch_on_merge = var.delete_branch_on_merge
  
  # Branch protection
  auto_init          = var.auto_init
  gitignore_template = var.gitignore_template
  license_template   = var.license_template
  
  # Topics for organization
  topics = var.topics
  
  # Template repository settings
  dynamic "template" {
    for_each = var.template_repository != null ? [var.template_repository] : []
    content {
      owner                = template.value.owner
      repository           = template.value.repository
      include_all_branches = template.value.include_all_branches
    }
  }
}

# Create default branch protection rule
resource "github_branch_protection" "main_protection" {
  count          = var.enable_branch_protection ? 1 : 0
  repository_id  = github_repository.team_repo.name
  pattern        = var.protected_branch_pattern
  
  required_status_checks {
    strict   = var.require_up_to_date_before_merge
    contexts = var.required_status_checks
  }
  
  required_pull_request_reviews {
    dismiss_stale_reviews           = var.dismiss_stale_reviews
    restrict_dismissals             = var.restrict_dismissals
    dismissal_restrictions          = var.dismissal_restrictions
    pull_request_bypassers          = var.pull_request_bypassers
    require_code_owner_reviews      = var.require_code_owner_reviews
    required_approving_review_count = var.required_approving_review_count
    require_last_push_approval      = var.require_last_push_approval
  }
  
  enforce_admins = var.enforce_admins
  
  dynamic "restrictions" {
    for_each = var.push_restrictions != null ? [var.push_restrictions] : []
    content {
      users  = restrictions.value.users
      teams  = restrictions.value.teams
      apps   = restrictions.value.apps
    }
  }
}

# Create repository environments for OIDC
resource "github_repository_environment" "team_environments" {
  for_each    = var.environments
  repository  = github_repository.team_repo.name
  environment = each.key
  
  # Deployment protection rules
  dynamic "deployment_protection_rules" {
    for_each = each.value.protection_rules != null ? each.value.protection_rules : []
    content {
      type = deployment_protection_rules.value.type
      id   = deployment_protection_rules.value.id
    }
  }
  
  # Environment protection rules
  dynamic "reviewers" {
    for_each = each.value.reviewers != null ? each.value.reviewers : []
    content {
      teams = reviewers.value.teams
      users = reviewers.value.users
    }
  }
  
  wait_timer = each.value.wait_timer
  can_admins_bypass = each.value.can_admins_bypass
  prevent_self_review = each.value.prevent_self_review
}

# Create environment secrets (for OIDC Role ARNs)
resource "github_actions_environment_secret" "oidc_secrets" {
  for_each = {
    for combo in flatten([
      for env_name, env_config in var.environments : [
        for secret_name, secret_value in env_config.secrets : {
          env_name     = env_name
          secret_name  = secret_name
          secret_value = secret_value
        }
      ]
    ]) : "${combo.env_name}-${combo.secret_name}" => combo
  }
  
  repository      = github_repository.team_repo.name
  environment     = each.value.env_name
  secret_name     = each.value.secret_name
  plaintext_value = each.value.secret_value
  
  depends_on = [github_repository_environment.team_environments]
}

# Create repository secrets (global to repo)
resource "github_actions_secret" "repo_secrets" {
  for_each        = var.repository_secrets
  repository      = github_repository.team_repo.name
  secret_name     = each.key
  plaintext_value = each.value
}

# Add team access to the repository
resource "github_team_repository" "team_access" {
  for_each   = var.team_access
  team_id    = each.key
  repository = github_repository.team_repo.name
  permission = each.value
}

# Add collaborators to the repository
resource "github_repository_collaborator" "collaborators" {
  for_each   = var.collaborators
  repository = github_repository.team_repo.name
  username   = each.key
  permission = each.value
}

# Create issue labels
resource "github_issue_label" "labels" {
  for_each    = var.issue_labels
  repository  = github_repository.team_repo.name
  name        = each.key
  color       = each.value.color
  description = each.value.description
}

# Create repository webhooks
resource "github_repository_webhook" "webhooks" {
  for_each   = var.webhooks
  repository = github_repository.team_repo.name
  
  configuration {
    url          = each.value.url
    content_type = each.value.content_type
    insecure_ssl = each.value.insecure_ssl
    secret       = each.value.secret
  }
  
  active = each.value.active
  events = each.value.events
}
