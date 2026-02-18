Title: Configure GitHub App Authentication for AAP 2.5 SCM Sync

Set up SCM integration between our GitHub repository and the existing Red Hat AAP 2.5 instance using GitHub App authentication (instead of PAT/SSH).

Tasks:
- [ ] Register/obtain GitHub App credentials from org admin
- [ ] Configure SCM credential in AAP 2.5 using GitHub App auth
- [ ] Link project in AAP 2.5 to this repository
- [ ] Validate SCM sync triggers on push/webhook

Notes: We do not own the AAP 2.5 platform — coordinate with platform team for credential setup access.




Title: Build and Publish Custom Execution Environment for Team Use

Create a team-owned Execution Environment (EE) image to standardize dependencies and collections.

Tasks:
- [ ] Define ee.yml with required Ansible collections and Python deps
- [ ] Build EE image using ansible-builder
- [ ] Push image to registry accessible by AAP 2.5
- [ ] Register EE in AAP 2.5 (coordinate with platform team)
- [ ] Validate EE is selectable in job templates

Notes: Target AAP 2.5 / ansible-builder 3.x compatibility.





Title: Configure Dynamic Inventory Source for Virtual Machines

Set up an inventory in AAP 2.5 to dynamically pull virtual machines for use in playbooks.

Tasks:
- [ ] Identify inventory source type (VMware, Azure, AWS, etc.)
- [ ] Create inventory credential in AAP 2.5
- [ ] Configure inventory source with appropriate filters/groups
- [ ] Test sync and validate hosts are populated
- [ ] Document group/variable structure for playbook targeting




Title: Request Service Account for Windows Server Connectivity (FIPS-Compliant)

AAP 2.5 is running with FIPS enabled, blocking NTLM/HTTP-based WinRM connections due to MD4 hash restriction.

Tasks:
- [ ] Submit service account request to AD/domain team
- [ ] Require account to support Kerberos authentication (NTLM blocked in FIPS mode)
- [ ] Configure WinRM to use Kerberos + HTTPS on target servers
- [ ] Update AAP 2.5 Windows machine credential to use Kerberos
- [ ] Validate connectivity from AAP 2.5 EE to a test Windows host

Blocker: `unsupported hash type md4 (in FIPS mode)` — NTLM over HTTP is not viable. Kerberos over HTTPS is the path forward.




Title: Develop Ansible Role for TFS Windows Server Deployment & Configuration

Build a reusable Ansible role to deploy and manage configuration on our TFS Windows servers.

Tasks:
- [ ] Define role structure (handlers, defaults, tasks, templates)
- [ ] Implement idempotent configuration tasks for TFS servers
- [ ] Integrate with team's custom EE (Issue #2)
- [ ] Test against inventory from dynamic source (Issue #3)
- [ ] Store role in this repo and document usage

Dependencies: Blocked on service account/Kerberos auth (Issue #4) for WinRM connectivity.
