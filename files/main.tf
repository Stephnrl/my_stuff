data "spacelift_account" "this" {}

locals {
  space_id = var.create_space ? spacelift_space.this[0].id : var.space_id

  # Repository-level values, with module defaults applied once.
  repos = {
    for repo_key, repo in var.repositories : repo_key => {
      repository         = coalesce(repo.repository, repo_key)
      branch             = coalesce(repo.branch, var.default_branch)
      terraform_provider = coalesce(repo.terraform_provider, var.default_terraform_provider)
      labels             = concat(var.common_labels, repo.labels)
      space_shares       = coalesce(repo.space_shares, var.default_space_shares)
      worker_pool_id     = repo.worker_pool_id
      description        = repo.description
      name               = repo.name
      modules            = repo.modules
    }
  }

  # One map per repository: a monorepo fans out into many modules, a flat repo
  # collapses to exactly one. Both branches produce identical object shapes so
  # the conditional type-checks.
  per_repo = [
    for repo_key, repo in local.repos :
    length(repo.modules) > 0 ? {

      # --- Monorepo -------------------------------------------------------
      for mod_key, mod in repo.modules :
      "${repo_key}:${mod_key}" => {
        name               = mod_key
        repository         = repo.repository
        branch             = repo.branch
        terraform_provider = coalesce(mod.terraform_provider, repo.terraform_provider)
        project_root       = coalesce(mod.project_root, mod_key)
        tag_prefix         = mod.tag_prefix != null ? mod.tag_prefix : mod_key
        description        = coalesce(mod.description, "${mod_key} module from ${repo.repository}")
        labels             = concat(repo.labels, mod.labels)
        space_shares       = repo.space_shares
        worker_pool_id     = repo.worker_pool_id
      }

      } : {

      # --- Flat repo ------------------------------------------------------
      # Name is inferred from a terraform-<provider>-<name> repository name,
      # falling back to the repository name itself.
      (repo_key) = {
        name = coalesce(
          repo.name,
          try(regex("^terraform-[^-]+-(.+)$", repo.repository)[0], repo.repository),
        )
        repository         = repo.repository
        branch             = repo.branch
        terraform_provider = repo.terraform_provider
        project_root       = null
        tag_prefix         = "" # plain vX.Y.Z tags
        description        = coalesce(repo.description, "Module from ${repo.repository}")
        labels             = repo.labels
        space_shares       = repo.space_shares
        worker_pool_id     = repo.worker_pool_id
      }
    }
  ]

  # One entry per Spacelift module, keyed "<repo>" or "<repo>:<module>".
  modules = length(local.per_repo) > 0 ? merge(local.per_repo...) : {}
}

resource "spacelift_space" "this" {
  count = var.create_space ? 1 : 0

  name             = var.space_name
  parent_space_id  = var.parent_space_id
  inherit_entities = var.inherit_entities
  description      = var.space_description
}

resource "spacelift_policy" "git_tag_versioning" {
  count = var.create_policy ? 1 : 0

  name        = var.policy_label
  type        = "GIT_PUSH"
  space_id    = local.space_id
  description = "Publishes a module version from a git tag. Monorepo modules use a <prefix>/vX.Y.Z tag, flat repos use vX.Y.Z."
  body        = file("${path.module}/policies/git-tag-versioning.rego")

  # Attaches to every module carrying var.policy_label.
  labels = ["autoattach:${var.policy_label}"]
}

resource "spacelift_module" "this" {
  for_each = local.modules

  name               = each.value.name
  terraform_provider = each.value.terraform_provider
  repository         = each.value.repository
  branch             = each.value.branch
  project_root       = each.value.project_root
  description        = each.value.description
  worker_pool_id     = each.value.worker_pool_id

  space_id     = local.space_id
  space_shares = each.value.space_shares

  protect_from_deletion = var.protect_from_deletion

  labels = concat(
    [var.policy_label],
    each.value.tag_prefix != "" ? ["tag-prefix:${each.value.tag_prefix}"] : [],
    each.value.labels,
  )

  lifecycle {
    precondition {
      condition = length(distinct([
        for m in values(local.modules) : lower("${m.terraform_provider}/${m.name}")
      ])) == length(local.modules)
      error_message = "Module slugs must be unique per Spacelift account: two entries in var.repositories resolve to the same name + terraform_provider pair."
    }

    precondition {
      condition = length(distinct([
        for m in values(local.modules) : "${m.repository}|${m.tag_prefix}"
      ])) == length(local.modules)
      error_message = "Two modules in the same repository share a tag prefix, so a single tag would publish both. Give each module a distinct tag_prefix."
    }
  }
}
