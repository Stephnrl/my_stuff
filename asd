Azure Image Building Pipeline - Security Architecture Review
Executive Summary
This document describes a two-phase automated image building and provisioning pipeline for RHEL 9 virtual machines in Azure GCC High Gov Cloud. The pipeline leverages HashiCorp Packer for image creation, HashiCorp Terraform for infrastructure provisioning, and Ansible for configuration management and security hardening. All automation executes via GitHub Enterprise internal runners, ensuring code execution remains within the organization's network boundary.
The pipeline produces STIG-hardened, FIPS-enabled RHEL 9 images that are stored in an Azure Compute Gallery for consumption by downstream infrastructure-as-code workflows.

Architecture Components
Automation Tooling

HashiCorp Packer: Builds and generalizes VM images from Azure Marketplace sources, executing provisioning scripts and Ansible playbooks before capturing the final image.
HashiCorp Terraform: Provisions infrastructure from Compute Gallery images with declarative configuration, enforcing security baselines at deployment time.
Ansible: Performs configuration management including STIG hardening, patching, FIPS enablement, compliance scanning, and endpoint agent installation.

Platform Environment

Cloud Environment: Microsoft Azure GCC High Government Cloud
CI/CD Platform: GitHub Enterprise with internal self-hosted runners
Artifact Storage: Azure Compute Gallery for golden image distribution
Package Management: Internal JFrog Artifactory mirrors for PyPI, Ansible Galaxy collections, RHEL repositories, and Microsoft packages


Workflow 1: Image Creation Pipeline
Overview
The image creation workflow produces a hardened, generalized RHEL 9 image suitable for organizational deployment. Packer orchestrates the build process, provisioning a temporary virtual machine, executing hardening procedures, and capturing the final image to the Compute Gallery.
Network Architecture
Packer utilizes pre-existing network infrastructure during the build process. The temporary build VM is deployed into an established Virtual Network and Subnet; Packer does not create or modify network resources. This ensures the build process adheres to existing network security controls and segmentation policies.
Build Process
Temporary Resource Creation: Packer creates ephemeral resources for the build process including a temporary VM, network interface, and OS disk. These resources exist only for the duration of the image build and are automatically cleaned up upon completion.
Base Image Sourcing: The pipeline sources a RHEL 9 base image from the Azure Marketplace, ensuring the starting point is a vendor-supported, unmodified operating system image.
Bootstrap Configuration: A shell provisioner configures the build VM to utilize internal package mirrors exclusively. This includes configuring pip/PyPI to reference the internal JFrog Artifactory mirror, configuring Ansible Galaxy to retrieve collections from the internal JFrog endpoint, and configuring RHEL DNF/YUM repositories to use internal JFrog mirrors including Microsoft package repositories. This configuration ensures all packages are sourced from approved, scanned repositories rather than public internet sources.
Tooling Installation: The bootstrap process installs Python 3.11 and Ansible Core 2.18.x, then clones the internal Ansible repository containing organizational playbooks and roles.
Patching and FIPS Enablement: Ansible executes a patching role that applies current security updates and enables FIPS 140-2 mode. Following this phase, the VM reboots to activate FIPS cryptographic modules and apply kernel updates.
STIG Hardening: After reboot, Ansible executes the Ansible Lockdown STIG RHEL 9 role, applying Defense Information Systems Agency (DISA) Security Technical Implementation Guide controls. Deviations from the baseline are documented and submitted separately for review.
Compliance Scanning: An OpenSCAP compliance scan executes against the hardened image to validate STIG implementation and generate a compliance percentage. Current baseline achieves approximately 80% compliance, with compensating controls documented for intentional deviations.
Image Generalization: A cleanup script removes temporary files and build artifacts. The Azure Linux Agent command waagent -force -deprovision+user generalizes the VM, removing machine-specific identifiers and preparing the image for replication.
Image Publication: Packer captures the generalized VM and publishes the resulting image to the Azure Compute Gallery, making it available for consumption by provisioning workflows.

Workflow 2: Image Provisioning Pipeline
Overview
The provisioning workflow deploys virtual machines from the hardened Compute Gallery image and performs final configuration including endpoint security agent installation. Terraform manages infrastructure creation while Ansible handles post-deployment configuration.
Infrastructure Provisioning
Image Sourcing: Terraform references the Packer-generated image from the Azure Compute Gallery, ensuring all deployed VMs inherit the hardened baseline configuration.
Virtual Machine Configuration: Terraform creates VMs with the following security controls enforced at provisioning time:
ControlSettingTrusted LaunchEnabledvTPMEnabledPassword AuthenticationDisabledNetwork Access PolicyDenyAllPublic Network AccessDisabledPublic IP AddressNone
Azure Extensions: Terraform deploys the following VM extensions during provisioning. The Azure Monitor Agent provides telemetry and log collection capabilities. The AADLoginForLinux extension enables Entra ID (Azure AD) authentication for SSH access, enforcing multi-factor authentication and role-based access control for VM access.
Post-Deployment Configuration
Elastic Agent Deployment: Ansible installs and configures the Elastic Agent, enrolling the agent against the organizational Fleet Server URL for centralized management and log shipping.
Microsoft Defender for Endpoint: Ansible installs Microsoft Defender for Endpoint, applies organizational configuration policies, and enrolls the agent with the Defender management plane.

Security Controls Summary
Supply Chain Security

All packages sourced from internal JFrog Artifactory mirrors
No direct internet access for package retrieval during build or deployment
Internal Ansible repository for controlled playbook distribution

Hardening and Compliance

DISA STIG RHEL 9 baseline applied via Ansible Lockdown
FIPS 140-2 cryptographic modules enabled
OpenSCAP compliance validation with documented findings

Network Security

Build process uses pre-approved VNet/Subnet infrastructure
Deployed VMs have no public IP addresses
Network access policy set to DenyAll by default
Azure NSGs provide network-layer access control (managed via Terraform)

Identity and Access

Password authentication disabled on all VMs
Entra ID authentication required for SSH access
Multi-factor authentication enforced via AADLoginForLinux
Role-based access control for VM login permissions

Endpoint Protection

Elastic Agent for security monitoring and log aggregation
Microsoft Defender for Endpoint for threat protection

Platform Security

Trusted Launch enabled for secure boot chain
Virtual TPM enabled for measured boot and key protection
GitHub Enterprise internal runners ensure CI/CD execution within organizational boundary


Documented Deviations
The following intentional deviations from the STIG baseline are implemented with compensating controls:
STIG ControlDeviationCompensating Controlfirewalld enabledDisabledAzure Network Security Groups provide network-layer filtering, managed as infrastructure-as-code via TerraformSELinux enforcingDisabledRequired for Microsoft Defender for Endpoint compatibility; endpoint detection and response provides application-layer protection
Additional deviations are documented in the attached deviation tracker and submitted for separate review.

Approval Request
This submission requests Security Architecture approval for the described image building and provisioning pipeline, including approval for the use of HashiCorp Packer, HashiCorp Terraform, and Ansible within the Azure GCC High Gov Cloud environment, operating via GitHub Enterprise internal runners.
Attached documentation includes architecture diagrams, STIG deviation tracker, and OpenSCAP scan results.
