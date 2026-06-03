We propose implementing a controlled GitHub custom runner image pipeline that follows a nonprod-to-prod promotion cycle.

The new process builds a bootstrap image, scans and validates it, generates security evidence, builds internalized runner image variants, deploys those variants to non-production, validates them against runner groups, and only then promotes the approved image to production.

At a high level, the solution introduces:

Scheduled GitHub workflow
→ Self-hosted enterprise runner on private AKS
→ Azure Gov OIDC federated access
→ ACR Task bootstrap build
→ Trivy security gate, SBOM, POA&M output
→ Dedicated private ACR agent pool for internal image builds
→ dotnet6 / dotnet8 / dotnet10 runner variants
→ Smoke and functional testing
→ Nonprod deployment and validation
→ Promotion gate
→ Prod ACR promotion
→ Production deployment and validation
→ GitHub release

This fixes the current problem by replacing manual, per-environment builds with a controlled, auditable promotion workflow. Instead of rebuilding images separately for each environment, the pipeline produces a validated image version and promotes that same version forward. This improves consistency, traceability, and confidence that production is using the same image that was tested in non-production.

The new CI/CD security gate also gives us a stronger enforcement point than relying on repository scanning alone. Trivy scan results, SBOM output, and POA&M tracking become part of the pipeline evidence. The build is evaluated before promotion, and findings are either remediated, documented, risk-managed, or blocked based on policy.
