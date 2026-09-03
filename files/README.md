# terraform-spacelift-module-registry

Registers Terraform module repositories in the Spacelift module registry and
wires up tag-driven, per-module semantic versioning. Handles both flat repos
(one module at the root) and monorepos (many modules in subdirectories), each
with an independent version counter.

## Usage

```hcl
module "module_registry" {
  source = "git::https://github.com/my-org/terraform-spacelift-module-registry.git?ref=v1.0.0"

  repositories = {
    # Monorepo: four modules, four independent version counters.
    "terraform-module-aws-networking" = {
      description = "Shared AWS networking building blocks"
      modules = {
        vpc     = { description = "VPC, IGW, NAT gateways" }
        dhcp    = { description = "DHCP option sets" }
        subnets = { description = "Subnet layouts" }

        # Module name and directory differ: registry address uses the
        # hyphenated name, project_root points at the underscored directory.
        tgw-routing = {
          project_root = "tgw_routing"
          description  = "Transit Gateway attachments and routing"
        }
      }
    }

    # Flat repo: name and provider inferred as "eks" / "aws".
    "terraform-aws-eks" = {
      description = "Opinionated EKS cluster"
    }

    # Flat repo not following the naming convention.
    "platform-rds" = {
      name               = "rds"
      terraform_provider = "aws"
      description        = "RDS instances with our standard parameter groups"
    }
  }
}
```

## Releasing

Tag format depends on the repository shape:

| Repository | Tag             | Publishes            |
| ---------- | --------------- | -------------------- |
| Monorepo   | `vpc/v1.3.0`    | only the vpc module  |
| Flat       | `v2.1.0`        | the repo's module    |

```bash
git tag vpc/v1.3.0 && git push origin vpc/v1.3.0
```

Check where a module actually is before tagging — Spacelift enforces strict
semver and will not let you skip a version:

```bash
git tag --list 'vpc/*' --sort=-v:refname | head -1
```

`terraform output release_commands` prints the right command per module.

## Calling this module more than once

The push policy is shared and auto-attaches by label, so exactly one invocation
should own it:

```hcl
module "registry_platform" {
  source       = "..."
  repositories = { ... }
  # owns the space and the policy
}

module "registry_data_team" {
  source        = "..."
  repositories  = { ... }
  create_space  = false
  create_policy = false
  space_id      = module.registry_platform.space_id
}
```

Two invocations both creating the policy would attach two identical policies to
every module, doubling evaluations for no benefit.

## Repository requirements

Each module directory (or the repo root, for a flat repo) needs a
`.spacelift/config.yml`:

```yaml
version: 1
# Placeholder. The real version comes from the git tag via the push policy.
module_version: 0.0.0
```

With no `tests:` block, versions are marked green immediately and no cloud
credentials are needed. Once you add test cases, Spacelift runs a real
init/plan/apply/destroy cycle and the modules need a cloud integration attached.

Modules must not contain a `backend` block.

## Notes

- The admin stack applying this must be `administrative = true`, and in `root`
  if `create_space` is true with `parent_space_id = "root"`.
- `default_space_shares = ["root"]` makes modules available account-wide.
  Sharing to a space also reaches its inheriting children. Set to `[]` to keep
  modules private to their own space.
- Module slugs are `terraform-<provider>-<name>` and must be unique per
  account. The module fails at plan time if two entries collide.
- Tags containing a slash create a ref directory, so once `vpc/v1.0.0` exists,
  git will refuse a tag named exactly `vpc` in the same repo.
