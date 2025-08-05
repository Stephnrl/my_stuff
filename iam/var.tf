# GitHub Repository Module Variables
# File: modules/github-repo/variables.tf

variable "repository_name" {
  description = "Name of the GitHub repository"
  type        = string
}

variable "repository_description" {
  description = "Description of the GitHub repository"
  type        = string
  default     = ""
}

variable "repository_visibility" {
  description = "Visibility of the repository (public, private, internal)"
  type        = string
  default     = "private"
}

# Repository features
variable "has_issues" {
  description = "Enable issues for the repository"
  type        = bool
  default     = true
}

variable "has_projects" {
  description = "Enable projects for the repository"
  type        = bool
  default     = false
}

variable "has_wiki" {
  description = "Enable wiki for the repository"
  type        = bool
  default     = false
}

variable "has_downloads" {
  description = "Enable downloads for the repository"
  type        = bool
  default     = false
}

variable "has_discussions" {
  description = "Enable discussions for the repository"
  type        = bool
  default     = false
}

# Merge settings
variable "allow_merge_commit" {
  description = "Allow merge commits"
  type        = bool
  default     = true
}

variable "allow_squash_merge" {
  description = "Allow squash merging"
  type        = bool
  default     = true
}

variable "allow_rebase_merge" {
  description = "Allow rebase merging"
  type        = bool
  default     = true
}

variable "delete_branch_on_merge" {
  description = "Delete branch on merge"
  type        = bool
  default     = true
}

# Repository initialization
variable "auto_init" {
  description = "Initialize repository with README"
  type        = bool
  default     = true
}

variable "gitignore_template" {
  description = "Gitignore template to use"
  type        = string
  default     = null
}

variable "license_template" {
  description = "License template to use"
  type        = string
  default     = null
}

variable "topics" {
  description = "Repository topics"
  type        = list(string)
  default     = []
}

# Template repository
variable "template_repository" {
  description = "Template repository to use"
  type = object({
    owner                = string
    repository           = string
    include_all_branches = bool
  })
  default = null
}

# Branch protection
variable "enable_branch_protection" {
  description = "Enable branch protection"
  type        = bool
  default     = false
}

variable "protected_branch_pattern" {
  description = "Branch pattern to protect"
  type        = string
  default     = "main"
}

variable "require_up_to_date_before_merge" {
  description = "Require branches to be up to date before merging"
  type        = bool
  default     = true
}

variable "required_status_checks" {
  description = "Required status checks"
  type        = list(string)
  default     = []
}

variable "dismiss_stale_reviews" {
  description = "Dismiss stale reviews when new commits are pushed"
  type        = bool
  default     = true
}

variable "restrict_dismissals" {
  description = "Restrict who can dismiss reviews"
  type        = bool
  default     = false
}

variable "dismissal_restrictions" {
  description = "Users/teams that can dismiss reviews"
  type        = list(string)
  default     = []
}

variable "pull_request_bypassers" {
  description = "Users/teams that can bypass PR requirements"
  type        = list(string)
  default     = []
}

variable "require_code_owner_reviews" {
  description = "Require code owner reviews"
  type        = bool
  default     = false
}

variable "required_approving_review_count" {
  description = "Number of required approving reviews"
  type        = number
  default     = 1
}

variable "require_last_push_approval" {
  description = "Require approval of last push"
  type        = bool
  default     = false
}

variable "enforce_admins" {
  description = "Enforce branch protection for admins"
  type        = bool
  default     = false
}

variable "push_restrictions" {
  description = "Push restrictions for the protected branch"
  type = object({
    users = list(string)
    teams = list(string)
    apps  = list(string)
  })
  default = null
}

# Environments (for OIDC)
variable "environments" {
  description = "Repository environments configuration"
  type = map(object({
    protection_rules = optional(list(object({
      type = string
      id   = number
    })))
    reviewers = optional(list(object({
      teams = optional(list(string))
      users = optional(list(string))
    })))
    wait_timer          = optional(number)
    can_admins_bypass   = optional(bool, true)
    prevent_self_review = optional(bool, false)
    secrets = optional(map(string), {})
  }))
  default = {}
}

# Repository secrets
variable "repository_secrets" {
  description = "Repository-level secrets"
  type        = map(string)
  default     = {}
  sensitive   = true
}

# Team access
variable "team_access" {
  description = "Team access permissions (team_id => permission)"
  type        = map(string)
  default     = {}
}

# Collaborators
variable "collaborators" {
  description = "Individual collaborator permissions (username => permission)"
  type        = map(string)
  default     = {}
}

# Issue labels
variable "issue_labels" {
  description = "Custom issue labels"
  type = map(object({
    color       = string
    description = string
  }))
  default = {}
}

# Webhooks
variable "webhooks" {
  description = "Repository webhooks"
  type = map(object({
    url          = string
    content_type = string
    insecure_ssl = bool
    secret       = string
    active       = bool
    events       = list(string)
  }))
  default = {}
}
