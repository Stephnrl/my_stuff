# Iron Bank (GitLab) → GitHub: Enterprise Image-Hardening Pipeline

A breakdown of how DoD Platform One's **Iron Bank** / **Repo One** container-hardening
system is wired, and how to replicate the architecture in GitHub.

> Most of Repo One is public, so the pipeline architecture below is reconstructed
> from the official Iron Bank pipeline docs and several real `dsop/...` container repos.

---

## How Iron Bank is organized

It's a **two-layer model**, which is the key insight for replicating it.

### One central pipeline repo, many thin consumer repos

- A single project, `ironbank-tools/ironbank-pipeline`, stores the pipeline code that
  **every** container hardening project under the `dsop` group uses to define its pipelines.
- Each image (postgres, openjdk17, pgadmin, etc.) lives in its **own repo** under `dsop/...`
  and carries only a small set of declarative files.
- The per-image repo contains **no pipeline logic** — it `include:`s the central pipeline.

> Governance and CI logic are centralized; image definitions are distributed.

### A per-image repo

```
container-project (feature-branch)
├── Dockerfile                 (required)
├── Dockerfile.arm64           (optional)
├── hardening_manifest.yaml    (required)
├── testing_manifest.yaml      (optional)
├── LICENSE                    (required)
├── README.md                  (required)
├── renovate.json              (if needed)
├── trufflehog-config.yaml     (if needed)
├── config/                    (if needed)
├── documentation/             (if needed)
├── scripts/                   (if needed)
└── .gitlab/                   (default)
```

Source code is **not** submitted to the repo.

### The `hardening_manifest.yaml` is the heart of it

It declares:

- Base image (`BASE_REGISTRY` / `BASE_IMAGE` / `BASE_TAG`)
- Image labels / metadata
- Maintainers
- A `resources` section listing every external artifact **with a checksum**

Dependencies not already in Iron Bank (binaries, builder images, etc.) must be declared
in `resources`; the pipeline downloads and pre-stages them as import artifacts during the
prebuild stage (Iron Bank stages these in Nexus).

### The build is offline by design

- The container build runs in an **offline environment**.
- The only network access is: resources listed in `hardening_manifest.yaml`, images from
  Registry1, and a set of **proxied package managers** (PyPI, Go proxy, npm, Rubygems).
- Any attempt to reach the internet is rejected by the cluster's egress policy and **fails the build**.
- Build method is locked down: **only a Dockerfile** in the build context is accepted —
  no Ansible/Terraform, no build scripts. `wget`/`curl` in build scripts are rejected even
  if never executed.

---

## The pipeline stages

| Stage | Job | What it does |
|---|---|---|
| setup | setup | Workspace setup, lint repo structure, verify required files exist |
| pre-build | import-artifacts | Download external resources from the manifest, validate checksums |
| build | build-amd64 / build-arm64 | Offline `docker build` from the Dockerfile |
| post-build | create-tar / create-sbom | Output image tarball; generate SBOMs (SPDX, CycloneDX, syft JSON via Anchore syft) |
| pre-scan | scan-logic | Diff SBOM against prior build to detect software changes |
| scan | openscap / twistlock / anchore | STIG compliance (OpenSCAP RHEL 8/9), vuln scan (Twistlock/Prisma), vuln+compliance+malware (Anchore + ClamAV) |
| pre-publish | vat | Push findings to the Vulnerability Assessment Tracker; compute ABC/ORA risk scores |
| publish | check-cves / generate-documentation / harbor | Log unjustified findings; generate CSVs; push signed image + SBOM + VAT attestation to Harbor |
| post-publish | manifest / upload-to-s3 | Sign multi-arch manifest list; upload docs to S3 for the website |

### Branch model = governance gate

| Branch | Pipeline behavior |
|---|---|
| Feature branches | Do **not** publish to Registry1 or push findings to Iron Bank |
| development | Does **not** publish; merge must be done by the Container Hardening Team (you can open the MR) |
| master | **Publishes** image to Registry1 + findings to Iron Bank; merge must be done by the Hardening Team |

Images and SBOM attestations are signed with **cosign**. **Renovate** auto-PRs dependency
bumps by reading the manifest's `resources` section.

### The three pillars

1. Centralized reusable pipeline + declarative per-image manifests
2. Airgapped reproducible builds with checksummed inputs
3. A scan → human-justify → sign → publish gate with an accreditation database (VAT)

---

## Mapping it to GitHub

| Iron Bank / GitLab | GitHub equivalent | Notes |
|---|---|---|
| `ironbank-pipeline` central repo + `include:` | **Reusable workflows** (`on: workflow_call`) in a shared repo, or composite actions | Direct analog. Callers use `uses: your-org/ci/.github/workflows/harden.yml@v1` |
| Thin per-image `.gitlab-ci.yml` | Thin caller workflow (~15 lines) | Keep `hardening_manifest.yaml` as-is — just YAML you parse in a setup step |
| Org enforcement of the pipeline | **Org rulesets / required workflows** + CODEOWNERS | Prevents teams bypassing the central pipeline |
| Offline build + egress deny | **Self-hosted runners** in a locked-down VPC/namespace with egress policy (NetworkPolicy / firewall) | GitHub-hosted runners can't do this; mandatory for true airgapped builds |
| Proxied PyPI/Go/npm/Rubygems | **Artifactory or Nexus pull-through caches** reachable from runners | Same pattern Iron Bank uses (Nexus) |
| Checksummed `resources` | Same manifest pattern + a verify step | Trivial to reimplement |
| Anchore / syft / Twistlock / OpenSCAP / ClamAV | `anchore/scan-action`, `anchore/sbom-action`, Trivy action, OpenSCAP container, ClamAV job | All have actions or CLIs. Trivy/Grype covers most of Anchore's vuln role |
| Findings → SARIF surfacing | **Code scanning (SARIF upload)** via GitHub Advanced Security | Findings UI for free |
| **VAT (justifications, ABC/ORA)** | **No drop-in equivalent** — custom | Options: in-repo waiver files (`.grype.yaml` / Trivy ignore + reasons), **Dependency-Track**, or a small app. Real work |
| cosign signing + SBOM attestation | **`actions/attest-build-provenance` + `attest-sbom`** (native), or keep cosign | GitHub's native attestations give SLSA provenance out of the box |
| Registry1 (Harbor) | **GHCR**, or run your own **Harbor / Artifactory** | Harbor gives scan-on-push + continuous rescan like Registry1 |
| Renovate (manifest-aware) | **Renovate app** (works on GitHub) or Dependabot | Renovate supports the custom-manager pattern they use |
| Continuous rescan of published images | **Scheduled workflow** (`on: schedule`) + registry scanning | Re-scans published images as new CVEs drop |

---

## What's worth copying, and what to think twice about

### Cheap, high-value wins (days, not months)

- Central reusable workflow + thin caller pattern
- Checksummed declarative manifest
- Mandatory hardened base images (pinned by digest, scanned)
- Scan gates with SBOM + signed attestations
- Org rulesets so nobody ships an unscanned image

### The expensive parts (these are what make Iron Bank *Iron Bank*)

**Airgapped offline build** — a real infrastructure project: self-hosted runners,
pull-through proxies, egress policy, and forcing every dependency to be declared and
checksummed. Worth it for supply-chain reproducibility, but ask whether your threat model
needs full network isolation, or whether "hardened base + scan gate + signed provenance"
already covers you. Many enterprises get 90% of the value without the airgap.

**VAT / human-justification / accreditation workflow** — no GitHub-native equivalent.
The DoD's real product is the *accreditation*: a tracked, auditable record of every finding
and its justification, with a risk score (ABC/ORA) gating publication. Replicating it means
Dependency-Track or a lightweight findings-and-waivers service. This is the hard 80% — don't
underestimate it.

### One trap to avoid

Don't mirror their exact stage names and tooling 1:1. Their tool choices (Twistlock,
Anchore Enterprise, OpenSCAP STIG profiles) are partly driven by DoD compliance mandates
you probably don't share. Copy the **architecture** — central pipeline, declarative
manifests, scan→justify→sign→publish gate, continuous rescan — and pick tools that fit your
own compliance regime.

---

## Reference links

- Iron Bank pipeline docs: https://docs-ironbank.dso.mil/quickstart/pipeline/
- Repository structure: https://docs-ironbank.dso.mil/hardening/repository-structure/
- Dockerfile requirements: https://docs-ironbank.dso.mil/hardening/dockerfile-requirements/
- Automating updates (Renovate): https://docs-ironbank.dso.mil/hardening/automating-updates/
- Central pipeline repo: https://repo1.dso.mil/ironbank-tools/ironbank-pipeline
