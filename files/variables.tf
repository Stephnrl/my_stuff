variable "repositories" {
  description = <<-EOT
    Repositories to register in the Spacelift module registry.

    The map key is the repository name (without the owner), unless `repository`
    is set explicitly.

    FLAT REPO - leave `modules` unset. One Spacelift module is created at the
    repository root, released with plain `vX.Y.Z` tags. The module name is
    inferred from a `terraform-<provider>-<name>` repository name, or can be
    set with `name`.

    MONOREPO - populate `modules`. Each entry becomes one Spacelift module with
    its own independent version counter. The map key is the module name, and
    both `project_root` and `tag_prefix` default to it, so `vpc = {}` means
    directory `vpc/` released with `vpc/vX.Y.Z` tags.
  EOT

  type = map(object({
    # Repository name without the owner. Defaults to the map key.
    repository = optional(string)

    # Only used for flat repos. Defaults to the name inferred from the
    # repository name, falling back to the repository name itself.
    name = optional(string)

    branch             = optional(string)
    terraform_provider = optional(string)
    description        = optional(string)
    labels             = optional(list(string), [])
    worker_pool_id     = optional(string)
    space_shares       = optional(list(string))

    modules = optional(map(object({
      # Directory in the repo. Defaults to the module key.
      project_root = optional(string)

      # Git tag prefix. Defaults to the module key, so tags look like
      # "<key>/v1.2.0". Set to "" to release this module with plain
      # "v1.2.0" tags (only sane if it is the sole module in the repo).
      tag_prefix = optional(string)

      terraform_provider = optional(string)
      description        = optional(string)
      labels             = optional(list(string), [])
    })), {})
  }))

  default = {}
}

# --- Space -----------------------------------------------------------------

variable "create_space" {
  description = "Create a dedicated space for the registry. Set false to reuse an existing space via `space_id`."
  type        = bool
  default     = true
}

variable "space_id" {
  description = "Existing space ID to place modules in. Required when `create_space` is false."
  type        = string
  default     = null
}

variable "space_name" {
  description = "Name of the space to create when `create_space` is true."
  type        = string
  default     = "modules"
}

variable "space_description" {
  description = "Description of the created space."
  type        = string
  default     = "Shared Terraform/OpenTofu module registry"
}

variable "parent_space_id" {
  description = "Parent of the created space."
  type        = string
  default     = "root"
}

variable "inherit_entities" {
  description = "Whether the created space inherits entities from its parent."
  type        = bool
  default     = true
}

variable "default_space_shares" {
  description = <<-EOT
    Spaces the modules are made available to, unless overridden per repository.
    Sharing to "root" reaches every space in the tree with inheritance enabled.
    Set to [] to keep modules private to their own space.
  EOT
  type        = list(string)
  default     = ["root"]
}

# --- Push policy -----------------------------------------------------------

variable "create_policy" {
  description = <<-EOT
    Create the tag-driven versioning push policy.

    Set to false when calling this module more than once in the same account -
    only one invocation should own the policy, otherwise every module ends up
    with duplicate attachments of an identical policy.
  EOT
  type        = bool
  default     = true
}

variable "policy_label" {
  description = <<-EOT
    Label applied to every module, and matched by the policy's
    `autoattach:<label>`. Must be identical across invocations that share
    a single policy.
  EOT
  type        = string
  default     = "git-tag-versioning"
}

# --- Defaults --------------------------------------------------------------

variable "default_branch" {
  description = "Tracked branch, unless overridden per repository."
  type        = string
  default     = "main"
}

variable "default_terraform_provider" {
  description = "Terraform provider name, unless overridden per repository or module."
  type        = string
  default     = "aws"
}

variable "common_labels" {
  description = "Labels applied to every module created by this invocation."
  type        = list(string)
  default     = []
}

variable "protect_from_deletion" {
  description = "Protect the created modules from accidental deletion."
  type        = bool
  default     = false
}
