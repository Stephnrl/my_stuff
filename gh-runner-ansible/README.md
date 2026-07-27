# github_runner

Ansible role for GitHub Actions self-hosted runners on Windows. Installs new
instances, re-registers existing ones, upgrades binaries, and removes runners —
at enterprise, organization or repository scope.

---

## One role or two?

**One role, four entry points, four playbooks.**

Install and re-register share roughly 80% of their logic: token minting, scope
URL construction, `config.cmd` argument assembly, service-account handling,
`SeServiceLogonRight`, directory ACLs, service start/verify. Splitting them into
two roles means two copies of `defaults/main.yml` that will drift the first time
someone changes a label scheme in one and not the other.

What *should* be separate is the **playbook**, because that is what a Spacelift
stack points at, and because these operations have very different blast radii.
So:

| Playbook | `github_runner_action` | Does |
|---|---|---|
| `playbooks/github_runner/install.yml` | `install` | Downloads the package, extracts into any missing instance dir, registers anything not yet configured. Idempotent — skips instances that already have a `.runner`. |
| `playbooks/github_runner/reregister.yml` | `reregister` | Touches nothing on disk. Unregisters then re-registers instances that already exist. |
| `playbooks/github_runner/upgrade.yml` | `upgrade` | Stops service, overlays a newer runner package, starts. For fleets pinned with `--disableupdate`. |
| `playbooks/github_runner/remove.yml` | `remove` | Unregisters, optionally deletes the directory. Gated behind `-e confirm_remove=yes`. |

The role also works via `tasks_from:` if you prefer that style:

```yaml
- ansible.builtin.include_role:
    name: github_runner
    tasks_from: reregister
```

---

## Layout

```
ansible.cfg
requirements.yml
inventories/
  prod/
    hosts.yml
    group_vars/
      gh_runners.yml          # scope, base dir, service account, instance list
playbooks/
  github_runner/
    install.yml
    reregister.yml
    upgrade.yml
    remove.yml
roles/
  github_runner/
    defaults/main.yml
    vars/main.yml             # computed API + config URLs per scope
    meta/main.yml
    meta/argument_specs.yml   # free input validation
    tasks/
      main.yml                # dispatch on github_runner_action
      preflight.yml
      token.yml               # mints registration/removal tokens via REST
      package.yml             # version resolution + download
      install.yml
      _install_instance.yml
      configure.yml           # register ONE instance (shared)
      unconfigure.yml         # unregister ONE instance (shared)
      service.yml             # service identity + start (shared)
      reregister.yml
      remove.yml
      upgrade.yml
      _upgrade_instance.yml
```

### Two things about your current paths

1. **`Roles/` needs to be `roles/`.** Ansible's default `roles_path` is
   lowercase, and Spacelift workers are Linux, so a capital `R` resolves on your
   Windows workstation and then fails in the stack. `ansible.cfg` here pins
   `roles_path = roles` explicitly so it is not left to defaults.
2. **`playbooks/gh_runner_agent/install.yml` is fine**, but the role is named
   `github_runner`, so I matched the directory to it. Pick one spelling —
   `gh_runner` or `github_runner` — and use it for the role, the playbook
   directory, and the variable prefix. Mixed prefixes are the thing that makes
   `grep` useless six months later.

---

## Tokens without the `gh` CLI

Yes — this is just a REST call, and the role does it with `ansible.builtin.uri`.
No `gh`, no `curl`, no Python dependencies beyond ansible-core.

| Scope | Registration | Removal |
|---|---|---|
| Enterprise | `POST /enterprises/{enterprise}/actions/runners/registration-token` | `.../remove-token` |
| Organization | `POST /orgs/{org}/actions/runners/registration-token` | `.../remove-token` |
| Repository | `POST /repos/{owner}/{repo}/actions/runners/registration-token` | `.../remove-token` |

**The enterprise-scope caveat matters for you.** GitHub's enterprise runner
endpoints accept a **classic PAT with the `manage_runners:enterprise` scope**
only. Fine-grained PATs, GitHub App installation tokens, and App user tokens are
all rejected at enterprise level. Org-scope endpoints are more flexible — a
GitHub App with the *Self-hosted runners* org permission (write), or a classic
PAT with `admin:org`, both work there.

So: set `github_runner_api_token` to a classic PAT and let the role mint tokens
per run. Both token types expire after one hour, which is why minting beats
storing them. If you would rather pass pre-minted tokens (you mentioned you have
them), set `github_runner_registration_token` and `github_runner_remove_token`
and the API calls are skipped entirely.

By default the API call runs on the control node (`github_runner_api_delegate:
control_node`) so the PAT never reaches the Windows host. Flip it to `target` if
only the runners have egress to `api.github.com`.

For GHE.com data residency, override `github_runner_api_url` and
`github_runner_server_url` with your `*.ghe.com` subdomain.

---

## Usage

```bash
ansible-galaxy collection install -r requirements.yml -p ./collections

# stand up anything missing under D:\enterprise-cloud-runners\
ansible-playbook playbooks/github_runner/install.yml

# re-register everything that already exists
ansible-playbook playbooks/github_runner/reregister.yml

# re-register just instances 1 and 3, one host at a time
ansible-playbook playbooks/github_runner/reregister.yml \
  -e 'only=["1","3"]' -e batch=1

# pin and roll a new runner version
ansible-playbook playbooks/github_runner/upgrade.yml -e github_runner_version=2.328.0

# decommission
ansible-playbook playbooks/github_runner/remove.yml \
  -e confirm_remove=yes -e github_runner_purge_dir_on_remove=true
```

Adding a fifth runner is one entry in `github_runner_instances` plus a re-run of
`install.yml`; existing instances are skipped because their `.runner` file is
already present.

---

## Spacelift wiring

Four stacks, all pointed at the same repo, each with a different
`ANSIBLE_PLAYBOOK` / playbook path. Put the shared secrets in one **context**
attached to all four:

| Env var | Type | Notes |
|---|---|---|
| `GH_RUNNER_API_TOKEN` | secret | classic PAT, `manage_runners:enterprise` |
| `GH_RUNNER_SVC_PASSWORD` | secret | SCM service account password |
| `ANSIBLE_WIN_USER` | plain | WinRM/PSRP account, must be a local admin on the runner host |
| `ANSIBLE_WIN_PASSWORD` | secret | |

`group_vars/gh_runners.yml` reads them with `lookup('ansible.builtin.env', ...)`,
so nothing lands in git. Mark `install.yml` and `reregister.yml` as
auto-deployable if you want; keep `remove.yml` on manual confirmation — it also
requires `-e confirm_remove=yes` as a second gate.

If you would rather use Ansible Vault, mount the vault password as a Spacelift
file and add `vault_password_file` to `ansible.cfg`.

---

## Windows notes worth knowing before you run this

**`config.cmd` refuses to run when `.runner` exists.** `--replace` handles the
*server-side* name collision, but not the local config. This is the single most
common reason a naive re-registration play fails. `configure.yml` therefore
stats `.runner` and includes `unconfigure.yml` first — which is also why
re-registering is safe to run against an already-healthy runner.

**Removal falls back gracefully.** If `config.cmd remove --token` fails (expired
token, runner already deleted in the UI, stale credentials), the role retries
with `--local`, which drops the local config without contacting GitHub. That
leaves an offline entry in GitHub which the next registration reclaims via
`--replace`.

**The service password does not go on the command line by default.**
`github_runner_service_credentials_method: win_service` lets `config.cmd` install
the service as `NETWORK SERVICE`, then uses `win_service` to set the logon
account. This keeps the password out of the Windows process list, and out of
`cmd.exe` quoting rules — relevant because `config.cmd` is a batch wrapper and a
`%` in your service password will be eaten by batch variable expansion. Set the
method to `config_cmd` if you need the original behaviour; the role
single-quotes and escapes arguments for PowerShell either way.

**Rights the service account needs**, both handled by the role:
- `SeServiceLogonRight` ("Log on as a service") — `github_runner_grant_logon_as_service`
- Modify on `D:\enterprise-cloud-runners\<n>` — `github_runner_grant_dir_acl`

**`--disableupdate` is on by default.** Without it, runners self-update and the
version you think you deployed drifts within days. With it, you own upgrades, so
schedule `upgrade.yml`.

**Runner names must be unique across the whole scope.** The default
`{{ inventory_hostname | lower }}-N` handles that as long as hostnames are
unique. If you ever clone the VM, re-register rather than copying the directory —
`.credentials` is bound to the runner identity.

**`no_log` is on for every task that touches a token or password.** Turn it off
with `-e github_runner_debug_commands=true` only from a workstation, never in
Spacelift. When `config.cmd` fails with logging suppressed, the role prints a
pointer to `<runner dir>\_diag` instead of a blank error.

**Not in the role, but worth doing:** a Defender exclusion for
`D:\enterprise-cloud-runners` and its `_work` trees. Real-time scanning of
`node_modules` and build output is the usual cause of "the runner got slower and
nobody changed anything".

---

## Verified

- All four playbooks pass `ansible-playbook --syntax-check` on ansible-core 2.21.
- `preflight.yml` was exercised against valid input, a duplicate instance `id`,
  and an invalid action — all assert as intended.
- The `config.cmd` argument builder was rendered against a service password
  containing `'`, `` ` `` and `$` and escapes correctly for PowerShell.

Not verified against live Windows hosts — run `install.yml` against one host with
`--check --diff` first, then a single real host, before the fleet.
