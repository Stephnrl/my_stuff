# terraform-aws-network

Internal Terraform modules for the landing zone transit gateway hub-and-spoke.
One repo, three modules, versioned by git tag.

## Why three modules

Module boundaries follow **account and state boundaries**, not resource types.
Each module runs with different credentials, in a different pipeline, at a
different time. They cannot be collapsed into one.

| Module | Runs in | Owns | Triggered by |
|---|---|---|---|
| `modules/tgw-hub` | netops account | TGW, route tables, RAM share + principals | onboarding a new spoke account |
| `modules/tgw-spoke` | member account | RAM share accept, VPC attachment | account vending |
| `modules/tgw-routing` | netops account | attachment accept, association, propagation | after a spoke attachment exists |

`tgw-routing` is only needed for a segmented topology. On a flat TGW
(`default_route_table_association` and `_propagation` both true) skip it.

## Order of operations (invitation flow)

```
1. netops   apply tgw-hub      -> creates TGW + share, adds spoke as principal
                                  (an invitation is generated)
2. spoke    apply tgw-spoke    -> accepts invitation, creates attachment
3. netops   apply tgw-routing  -> accepts attachment, associates + propagates
```

Step 1 must fully complete before step 2. RAM invitations are eventually
consistent for a few seconds and **expire after 7 days**, so a spoke pipeline
that sits queued past that window will fail with "no invitation found" and
needs a re-run of step 1.

The step 2 -> step 3 handoff is the real design decision. Options:

1. **Flat topology.** Skip `tgw-routing` entirely. Zero coordination.
2. **EventBridge + Lambda in the hub.** Fires on attachment creation, reads the
   `Segment` tag, associates to the matching route table. Keeps the two
   pipelines fully decoupled. Where most mature setups land.
3. **Ordered pipeline.** Hub runs after spokes and discovers attachments via
   the `aws_ec2_transit_gateway_attachments` data source. Works, but couples
   apply ordering across repos.

## Sourcing

Subdirectories use the `//` separator. Always pin `?ref` to a tag, never a branch.

```hcl
module "tgw_hub" {
  source = "git::https://github.com/acme/terraform-aws-network.git//modules/tgw-hub?ref=v0.1.0"
  # ...
}
```

SSH works too if your runners have a deploy key:

```hcl
source = "git::ssh://git@github.com/acme/terraform-aws-network.git//modules/tgw-hub?ref=v0.1.0"
```

## Cloning an internal repo from GitHub Actions

**AWS OIDC does not help here.** OIDC gets Terraform into AWS; it grants no
GitHub repo access. The default `GITHUB_TOKEN` is scoped to the calling repo
only, so `terraform init` cannot clone this repo with it. You need one of:

- a **GitHub App** installation token (recommended — short-lived, scopable to
  this repo only, no user attached)
- a fine-grained PAT with `Contents: read` on this repo
- a deploy key, if using SSH sources

Then rewrite the URL prefix before `terraform init`:

```yaml
- run: |
    git config --global url."https://x-access-token:${{ steps.modules-token.outputs.token }}@github.com/".insteadOf "https://github.com/"
```

Full example in `examples/github-workflow/terraform.yml`.

## Versioning

Tag the whole repo (`v0.1.0`, `v0.2.0`) and move all consumers together. It is
the simplest thing that works and keeps the compatibility matrix trivial.

If modules later need independent release cadence, `?ref` accepts any git ref,
so per-module tags like `tgw-spoke/v1.4.0` work — but don't reach for that
until something actually forces it.

## Provider configuration

These modules declare no `provider` blocks. Root modules configure providers
and pass them in. Prefer one root module per account over one root module with
many aliased providers: stock Terraform cannot `for_each` a provider block, so
the alias-heavy pattern means editing HCL for every new account and gives you a
single state file whose blast radius covers every attachment in the org.

## Migrating to org-level RAM sharing

When you enable `aws_ram_sharing_with_organization` later:

1. Enable it from the management account.
2. Add the OU ARN to `shared_principals` alongside the existing account IDs.
3. Verify with `aws ram get-resource-share-associations`.
4. Remove the per-account IDs in a separate apply.
5. Set `accept_ram_share = false` in every spoke and `terraform state rm
   module.tgw_attachment.aws_ram_resource_share_accepter.this[0]`.

Steps 2 and 4 must be separate applies — changing a principal in place is a
destroy-then-create and would briefly revoke the share.
