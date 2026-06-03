The main technical change is the introduction of an automated image promotion pipeline using GitHub Actions, Azure Government, Azure Container Registry, ACR Tasks, private ACR agent pools, and downstream Terraform/Helm deployments.

New or changed components include:

Area	Change
GitHub Actions	Scheduled workflow for automated image build and promotion
GitHub Runner	Self-hosted enterprise runner hosted in private AKS
Azure Gov Access	OIDC federated access instead of static credentials
ACR Tasks	Bootstrap image build using ACR Tasks
Private ACR Agent Pool	Internal image build using Azure-managed, VNet-attached ACR agent pool
Security Gate	Trivy scan, SBOM generation, POA&M artifact generation
Deployment	Repository dispatch to downstream Terraform/Helm deployment repo
Validation	Nonprod and production runs-on validation across runner groups
Release	GitHub release of approved image version

A key architecture distinction is that the default/public ACR Task pool is Azure-managed compute and not inside the customer VNet, while the dedicated private ACR agent pool is Azure-managed but attached to the customer VNet. The private pool is used for internalized builds that require access to internal CA trust, JFrog mirrors, and private network resources.
