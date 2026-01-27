Short Description:
Deploy new HSM-enabled Key Vault for DigiCert certificate management via Terraform
Description:
Provision a new Azure Key Vault with HSM capability to store and manage DigiCert certificates per updated security requirements. Infrastructure deployed via GitHub Actions using Terraform. The Key Vault will be configured with public access disabled and a private endpoint for secure access. This is net-new infrastructure with no modifications to existing production resources.
Communication Plan:
No communication required. This is a net-new resource with no dependencies or impact to existing services or users.
Justification:
New organizational requirement mandates HSM-backed Key Vault for certificate management. DigiCert certificates must be stored in HSM-enabled vaults to meet compliance and security standards.
Implementation Plan:

Terraform code merged to main branch triggers GitHub Actions workflow
Workflow provisions Key Vault with HSM SKU
Configure private endpoint for Key Vault access
Disable public network access
Import/generate DigiCert certificate

Risk and Impact Analysis:

Risk: Low — net-new infrastructure only, no changes to existing resources
Impact: None — no production services depend on this resource
Blast radius: Zero — isolated resource with no downstream dependencies

Backout Plan:
Run terraform destroy targeting the Key Vault resource, or delete resource group if isolated. No rollback of existing systems required as this is additive infrastructure.
Test Plan:

Validate Terraform plan output prior to apply
Confirm Key Vault created with correct SKU (HSM)
Verify public access is disabled
Confirm private endpoint connectivity

Verification Plan:

Confirm Key Vault exists in Azure Portal/CLI
Validate HSM SKU configuration
Test certificate access via private endpoint
Verify public access returns denied/unreachable
