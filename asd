# Task Completion Notes — AWS Landing Zone

Copy each note into the Planner task before marking it complete.

---

## Bootstrap Module

---

### S3 backend state bucket + DynamoDB lock table

**Resolved**
- S3 bucket created with versioning enabled, SSE-S3/SSE-KMS encryption at rest, and public access blocked
- Bucket policy restricts access to the Terraform execution role only
- DynamoDB table created for state locking with `LockID` as partition key
- `backend.tf` configured and `terraform init` completed successfully with remote state
- Confirmed state file writes and lock acquisition/release on plan and apply

---

### OIDC identity provider for GitHub Actions

**Resolved**
- IAM OIDC identity provider created for `token.actions.githubusercontent.com`
- Thumbprint list configured per GitHub's published certificate chain
- Audience set to `sts.amazonaws.com`
- Provider ARN output for use in trust policy on the execution role

---

### IAM role with OIDC trust policy

**Resolved**
- IAM role created with trust policy scoped to the GitHub OIDC provider
- Trust condition restricts `sub` claim to the specific repo and branch/environment (e.g., `repo:org/repo-name:environment:production`)
- Role ARN output and passed downstream to GitHub environment variable task
- Confirmed `sts:AssumeRoleWithWebIdentity` works from a test GHA run

---

### IAM policy scoping (least privilege for TF apply)

**Resolved**
- Custom IAM policy attached to the Terraform execution role
- Permissions scoped to only the AWS services and actions required by the Terraform modules (VPC, EKS, IAM, S3, CloudWatch, Config, GuardDuty, etc.)
- No wildcard (`*`) actions — all actions explicitly listed
- Resource ARNs constrained where possible (region, account ID, resource name patterns)
- Policy validated with IAM Access Analyzer or `simulate-principal-policy`

---

### GHA workflow — save role ARN as env variable

**Resolved**
- GitHub environment created (e.g., `aws-landing-zone` or per-environment: `dev`, `prod`)
- Role ARN saved as a GitHub environment variable (`AWS_ROLE_ARN`)
- Additional environment variables set as needed: `AWS_REGION`, `TF_STATE_BUCKET`, `TF_LOCK_TABLE`
- Workflow references `${{ vars.AWS_ROLE_ARN }}` in the `aws-actions/configure-aws-credentials` step
- Confirmed variables are accessible in a test workflow run

---

### Validate assume-role from GHA runner

**Resolved**
- End-to-end test: GHA workflow triggered, assumed role via OIDC, ran `aws sts get-caller-identity` successfully
- Confirmed the assumed role identity matches the expected role ARN and account
- `terraform plan` executed successfully from the GHA runner using the assumed role
- `terraform apply` executed successfully with state written to the S3 backend
- No hardcoded credentials in the workflow — OIDC only

---

## Network Module

---

### VPC — CIDR planning + Terraform resource

**Resolved**
- CIDR block allocated per the network IP address plan (no overlap with existing VPCs or on-prem ranges)
- VPC created with DNS support and DNS hostnames enabled
- Secondary CIDR blocks added if required for EKS pod networking
- VPC ID output for downstream module consumption
- CIDR documented in the IP address registry / IPAM

---

### Subnets — public / private / isolated, multi-AZ

**Resolved**
- Public, private, and isolated (no egress) subnet tiers created across 3 AZs minimum
- CIDR ranges sized appropriately per tier (larger ranges for private/pod subnets)
- Subnets tagged with `kubernetes.io/role/elb` and `kubernetes.io/role/internal-elb` for EKS load balancer auto-discovery
- `map_public_ip_on_launch` set to `false` on private and isolated subnets
- Subnet IDs output grouped by tier for downstream consumption

---

### Transit Gateway attachment + route tables

**Resolved**
- TGW attachment created from the new VPC to the shared Transit Gateway
- TGW route table association and propagation configured
- VPC route tables updated with `0.0.0.0/0` or specific CIDRs pointing to the TGW attachment for cross-VPC and on-prem traffic
- Confirmed connectivity to shared services VPC and/or on-prem via TGW
- TGW attachment tagged for identification in the network account

---

### DHCP option set (custom DNS, NTP)

**Resolved**
- Custom DHCP option set created with internal DNS servers (e.g., Route 53 Resolver endpoints or on-prem DNS)
- NTP servers configured if required by compliance policy
- Domain name set to match internal domain (e.g., `ec2.internal` or custom)
- DHCP option set associated with the VPC
- Verified instances resolve internal DNS names correctly

---

### NACLs — baseline deny rules per tier

**Resolved**
- Custom NACLs created and associated with each subnet tier (public, private, isolated)
- Inbound and outbound rules follow a least-privilege baseline:
  - Public: allows HTTPS inbound, ephemeral ports outbound
  - Private: allows traffic from public tier and TGW CIDRs, denies direct internet inbound
  - Isolated: denies all internet-bound traffic (inbound and outbound)
- Rule numbers ordered with room for future insertions (e.g., 100, 200, 300)
- Explicit deny-all rule confirmed at the bottom of each NACL

---

### Route tables — public, private, TGW routes

**Resolved**
- Public route table: `0.0.0.0/0` → Internet Gateway
- Private route table: `0.0.0.0/0` → NAT Gateway, internal CIDRs → TGW
- Isolated route table: internal CIDRs → TGW only (no default route)
- Each route table associated with the correct subnet tier
- Routes verified with `aws ec2 describe-route-tables` or console inspection

---

### NAT Gateway / VPC endpoints for private subnets

**Resolved**
- NAT Gateway deployed in each AZ (or single AZ if cost-optimized for non-prod)
- Elastic IPs allocated and associated with NAT Gateways
- VPC Gateway Endpoints created for S3 and DynamoDB (free, avoids NAT charges)
- VPC Interface Endpoints created for key services if private subnet workloads require them (STS, ECR, CloudWatch Logs, etc.)
- Private subnet route tables updated to route through NAT and endpoints
- Confirmed private subnet instances can reach the internet and AWS APIs

---

### VPC Flow Logs enabled

**Resolved**
- VPC Flow Logs enabled at the VPC level (captures all ENIs)
- Log destination configured: CloudWatch Log Group and/or S3 bucket in the security account
- IAM role created with permissions to publish flow logs to the destination
- Log format includes all available fields (v5 custom format recommended)
- Retention period set per compliance requirements (e.g., 365 days)
- Confirmed flow log records are appearing in the destination

---

## Shared EKS Baseline (CMMC L2)

---

### EKS cluster — private API, encryption at rest

**Resolved**
- EKS cluster created with private API endpoint enabled, public endpoint disabled (or restricted to known CIDRs)
- KMS key created and configured for envelope encryption of Kubernetes secrets at rest
- Cluster security group restricts ingress to VPC CIDRs and TGW ranges only
- Kubernetes version set to a supported and patched release
- Cluster endpoint verified accessible from within the VPC / bastion / VPN

---

### Managed node groups — encrypted EBS, IMDSv2

**Resolved**
- Managed node groups created with encrypted EBS volumes (KMS CMK or aws/ebs)
- Launch template configured with `http_tokens = required` (IMDSv2 enforced) and `http_put_response_hop_limit = 1`
- Node IAM role has minimal permissions (EKS worker policy, CNI policy, ECR read)
- Node groups deployed across private subnets in multiple AZs
- Confirmed nodes join the cluster and report `Ready`

---

### Pod Identity agent + SA mappings

**Resolved**
- EKS Pod Identity Agent add-on installed and running on all nodes
- Pod Identity associations created mapping Kubernetes service accounts to IAM roles
- Verified pods using annotated service accounts can call AWS APIs with the expected role
- No IRSA fallback configured unless explicitly needed for backward compatibility
- SA-to-role mappings documented for each workload

---

### Wiz agent connector — DaemonSet / Helm

**Resolved**
- Wiz Kubernetes connector created in the Wiz tenant for this cluster
- Helm chart deployed (or DaemonSet applied) using the connector credentials
- Wiz agent pods running on all nodes (confirmed via `kubectl get ds -n wiz`)
- Cluster appearing in the Wiz inventory with vulnerabilities and misconfiguration findings populating
- Image scanning and runtime protection policies configured per org baseline

---

### Audit logging (control plane + data plane)

**Resolved**
- EKS control plane logging enabled for all log types: `api`, `audit`, `authenticator`, `controllerManager`, `scheduler`
- Logs shipping to CloudWatch Log Group in the security account (or local account with cross-account subscription)
- Data plane logging: Fluent Bit or CloudWatch agent DaemonSet deployed, forwarding container stdout/stderr and node logs
- Log retention set per CMMC requirements (minimum 1 year recommended)
- Confirmed audit log entries visible in CloudWatch for API calls (e.g., `kubectl` commands)

---

### Network policies / pod security standards

**Resolved**
- Default deny-all NetworkPolicy applied to every team namespace (ingress and egress)
- Allow policies created only for expected traffic patterns (e.g., within namespace, to CoreDNS, to specific external services)
- Pod Security Standards enforced at the namespace level:
  - `restricted` profile for team namespaces (no privileged containers, no host networking, read-only root FS, non-root)
  - `baseline` or `privileged` only for system namespaces (`kube-system`, `wiz`, monitoring)
- Confirmed a privileged pod is rejected in a team namespace
- CNI plugin supports NetworkPolicy enforcement (VPC-CNI with network policy agent or Calico)

---

### Secrets encryption (KMS envelope)

**Resolved**
- KMS key created with appropriate key policy (EKS service, cluster role, and admin access)
- EKS cluster configured with `encryption_config` block referencing the KMS key for `secrets` resource
- Verified: created a Kubernetes secret, confirmed it is stored encrypted in etcd via KMS
- Key rotation enabled on the KMS CMK (annual automatic rotation)
- KMS key ARN documented and tagged

---

### CoreDNS, kube-proxy, VPC-CNI add-on configs

**Resolved**
- CoreDNS add-on updated to latest compatible version, replica count and resource requests tuned
- kube-proxy add-on updated, running in `iptables` or `ipvs` mode as appropriate
- VPC-CNI add-on updated to latest version with `ENABLE_PREFIX_DELEGATION` set if using large pod counts
- `AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG` enabled if using secondary CIDRs for pods
- All add-ons confirmed healthy via `kubectl get ds,deploy -n kube-system`

---

### Cluster autoscaler / Karpenter with Pod Identity

**Resolved**
- Karpenter (or Cluster Autoscaler) deployed with Pod Identity for AWS API access (EC2, ASG, pricing)
- NodePool / Provisioner CRDs configured with instance type constraints, subnet selectors, and security group selectors
- Scaling tested: deployed a workload that exceeds current capacity, confirmed new nodes launched and pods scheduled
- Scale-down confirmed: removed workload, verified nodes drained and terminated within the configured TTL
- Disruption budgets and consolidation policies configured to avoid unnecessary churn
