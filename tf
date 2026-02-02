Architecture Review Request: Custom ARC Runner Image
Subject: Architecture Review – Custom Ephemeral Runner Image for GitHub Actions Scale Sets (ARC)

1. Overview
We are requesting an architecture review for a custom GitHub Actions Runner image. This image will be deployed via the Actions Runner Controller (ARC) using the Scale Set runner orchestration. The goal is to provide a standardized, compliant, and tool-rich environment for multiple development teams while maintaining strict security boundaries.

2. Deployment Architecture
Orchestration: GitHub Actions Runner Controller (ARC).

Runner Type: Scale Set Runners (Ephemeral).

Workflow:

A Persistent Listener Pod monitors the GitHub job queue.

Upon a job trigger, a Runner Pod is spun up using the custom image.

The Runner Pod is destroyed immediately after the job completes (Zero-persistence).

Infrastructure: Azure GovCloud (DoD compliance).

3. Supply Chain & Provenance
To ensure compliance with DoD/Azure GovCloud requirements, we have implemented a "Internal-Only" pull-through pattern:

Base Image: Red Hat Universal Base Image (UBI) 9, sourced directly from Iron Bank (Platform One).

Package Management: 100% of software installations are routed through internal JFrog Artifactory remote mirrors.

No direct outbound connections to public repositories (PyPI, npm, Microsoft, etc.) during the build.

Mirrors include: UBI AppStream/BaseOS, EPEL, NodeSource, Microsoft (for .NET/PowerShell), and HashiCorp.

Image Storage: Completed images are scanned and stored in a private JFrog Docker registry.

4. Image Specifications (Tooling)
The image is designed as a "heavy" runner to support cross-functional teams (Cloud, AppDev, Infrastructure).

Core Runtimes: Python 3.12.8, Node 24.13.0, .NET 10 & 8 (LTS), Java OpenJDK 17.0.18.

Cloud/IAC: Azure CLI 2.82.0, AWS CLI 2.33.11, Terraform 1.5.7, Packer 1.14.3.

K8s/Native: Kubectl 1.32.11, eksctl 0.221.0, Helm v4.0.4.

System/VCS: Git LFS 3.7.1, PowerShell 7.5.3, JFrog CLI 2.90.0.

5. Security Controls
Ephemerality: Pods are short-lived, reducing the blast radius of any potential compromise.

Rootless Execution: (Optional/Recommended) Mention if you are running the runner process as a non-privileged runner user.

Network Isolation: Runners operate within the internal VNET with traffic inspected via Azure Firewall/NSGs.

Supporting Documentation
Dockerfiles: (Attached) Demonstrating the FROM instruction pointing to Iron Bank and repository configurations pointing to JFrog.

Tooling Manifest: Complete list of versions and checksums.
