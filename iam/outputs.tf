# GitHub Repository Module Outputs
# File: modules/github-repo/outputs.tf

output "repository_id" {
  description = "GitHub repository ID"
  value       = github_repository.team_repo.repo_id
}

output "repository_name" {
  description = "GitHub repository name"
  value       = github_repository.team_repo.name
}

output "repository_full_name" {
  description = "GitHub repository full name (owner/repo)"
  value       = github_repository.team_repo.full_name
}

output "repository_url" {
  description = "GitHub repository URL"
  value       = github_repository.team_repo.html_url
}

output "repository_ssh_clone_url" {
  description = "SSH clone URL"
  value       = github_repository.team_repo.ssh_clone_url
}

output "repository_http_clone_url" {
  description = "HTTP clone URL"
  value       = github_repository.team_repo.http_clone_url
}

output "repository_git_clone_url" {
  description = "Git clone URL"
  value       = github_repository.team_repo.git_clone_url
}

output "default_branch" {
  description = "Default branch name"
  value       = github_repository.team_repo.default_branch
}

output "node_id" {
  description = "GitHub repository node ID"
  value       = github_repository.team_repo.node_id
}

output "environments" {
  description = "Created repository environments"
  value = {
    for env_name, env in github_repository_environment.team_environments : env_name => {
      id   = env.id
      name = env.environment
    }
  }
}

output "environment_secrets" {
  description = "Environment secrets created"
  value = {
    for key, secret in github_actions_environment_secret.oidc_secrets : key => {
      environment = secret.environment
      secret_name = secret.secret_name
    }
  }
  sensitive = true
}

output "repository_secrets" {
  description = "Repository secrets created"
  value = {
    for name, secret in github_actions_secret.repo_secrets : name => {
      secret_name = secret.secret_name
    }
  }
  sensitive = true
}

output "team_access" {
  description = "Team access granted"
  value = {
    for team_id, access in github_team_repository.team_access : team_id => {
      team_id    = access.team_id
      permission = access.permission
    }
  }
}

output "collaborators" {
  description = "Collaborators added"
  value = {
    for username, collab in github_repository_collaborator.collaborators : username => {
      username   = collab.username
      permission = collab.permission
    }
  }
}

output "branch_protection" {
  description = "Branch protection configuration"
  value = var.enable_branch_protection ? {
    pattern    = github_branch_protection.main_protection[0].pattern
    repository = github_branch_protection.main_protection[0].repository_id
  } : null
}

output "webhooks" {
  description = "Repository webhooks created"
  value = {
    for name, webhook in github_repository_webhook.webhooks : name => {
      id  = webhook.id
      url = webhook.configuration.0.url
    }
  }
  sensitive = true
}
