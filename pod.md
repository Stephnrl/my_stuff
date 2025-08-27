# Bottlerocket x86_64 FIPS: Our Container Security Strategy

## Overview

This document explains our decision to adopt **AWS Bottlerocket x86_64 FIPS** as the operating system for our EKS worker nodes, instead of traditional Amazon Linux 2 (AL2) or Amazon Linux 2023 (AL2023).

## Operating System Comparison

### Amazon Linux 2 / Amazon Linux 2023 (Traditional Approach)

**Characteristics:**
- General-purpose Linux distribution
- Full package manager (yum/dnf)
- SSH access enabled by default
- Supports wide variety of workloads
- Traditional mutable infrastructure
- 1,000+ installed packages

**Security Posture:**
- ⚠️ **Large Attack Surface**: Hundreds of unnecessary packages and services
- ⚠️ **Mutable System**: Files can be modified at runtime
- ⚠️ **Package Management**: Requires ongoing security patching
- ⚠️ **SSH Access**: Additional attack vector
- ⚠️ **Multi-purpose Design**: Not optimized for container security

### AWS Bottlerocket x86_64 FIPS ⭐ **Our Choice**

**Characteristics:**
- Purpose-built container-optimized Linux
- Minimal package set (~50 packages vs 1,000+)
- No SSH access by default
- API-driven configuration
- Immutable infrastructure design
- FIPS 140-2 validated cryptographic modules

**Security Posture:**
- ✅ **Minimal Attack Surface**: Only container runtime and essential components
- ✅ **Immutable System**: Cannot be modified at runtime
- ✅ **No Package Manager**: Eliminates package-based attack vectors
- ✅ **Secure by Default**: Hardened configuration out of the box
- ✅ **FIPS Compliance**: Government-grade cryptographic security

## Security Advantages

### 1. **Drastically Reduced Attack Surface**

| Component | AL2/AL2023 | Bottlerocket FIPS |
|-----------|------------|-------------------|
| **Installed Packages** | 1,000+ | ~50 |
| **Running Services** | 20-30 | 5-8 |
| **Network Ports** | Multiple | Minimal |
| **System Binaries** | 500+ | <100 |
| **SSH Access** | Enabled | Disabled |

**Attack Surface Comparison:**
```
AL2/AL2023: [SSH][Package Manager][System Tools][Libraries][Services][Container Runtime]
                    ↑ Multiple potential entry points

Bottlerocket: [Essential Services][Container Runtime]
                    ↑ Minimal, hardened entry points only
```

### 2. **Immutable Infrastructure Security**

**Traditional Linux (AL2/AL2023):**
```bash
# Mutable system - files can be changed
$ sudo vi /etc/ssh/sshd_config
$ sudo systemctl restart sshd
$ sudo yum install malicious-package
# ⚠️ System state can drift and be compromised
```

**Bottlerocket:**
```bash
# Immutable system - core OS cannot be modified
$ sudo vi /etc/ssh/sshd_config  # File doesn't exist
$ sudo yum install anything      # No package manager
$ sudo systemctl edit anything   # Limited system access
# ✅ System integrity maintained
```

### 3. **FIPS 140-2 Cryptographic Compliance**

**Why FIPS Matters:**
- **Government Requirements**: Mandatory for federal systems
- **Regulatory Compliance**: Required in finance, healthcare, defense
- **Enhanced Cryptography**: Validated cryptographic modules
- **Security Assurance**: Rigorous testing and certification

**FIPS Components in Bottlerocket:**
```bash
# FIPS-validated cryptographic modules
OpenSSL FIPS Provider      # Cryptographic operations
Linux Kernel Crypto API    # Kernel-level cryptography  
containerd                 # Container runtime security
kubelet                    # Kubernetes node security
```

### 4. **Container-Optimized Security**

**What's Included (Security-Focused):**
- Container runtime (containerd)
- Kubernetes components (kubelet, kube-proxy)
- Essential system services only
- AWS integrations (CloudWatch, SSM)
- Network security tools

**What's Excluded (Attack Surface Reduction):**
- Package managers (yum, apt, dnf)
- Development tools (gcc, make, git)
- Text editors (vi, nano, emacs)
- SSH server and clients
- Unnecessary system utilities

## Operational Security Benefits

### 1. **Image-Based Updates**

**Traditional OS Updates (AL2/AL2023):**
```bash
# Package-by-package updates
sudo yum update kernel           # Potential for partial failures
sudo yum update openssh         # Complex dependency chains
sudo yum update docker          # Service restart required
# ⚠️ System can end up in inconsistent state
```

**Bottlerocket Atomic Updates:**
```bash
# Complete image replacement
apiclient update apply          # Atomic operation
# ✅ Either fully updated or unchanged - no partial states
# ✅ Automatic rollback on failure
# ✅ Consistent, predictable outcomes
```

### 2. **Configuration as Code**

**Traditional Configuration:**
```bash
# Manual, error-prone configuration
sudo vi /etc/kubernetes/kubelet/kubelet-config.json
sudo systemctl restart kubelet
sudo vi /etc/docker/daemon.json
# ⚠️ Configuration drift over time
```

**Bottlerocket API-Driven Configuration:**
```bash
# Declarative, version-controlled configuration
apiclient set kubernetes.cluster-name=my-cluster
apiclient set kernel.lockdown=integrity
# ✅ Configuration is auditable and repeatable
# ✅ No manual system modifications
```

### 3. **Enhanced Monitoring and Compliance**

```bash
# Built-in security monitoring
apiclient get system.uptime        # System integrity checks
apiclient get kernel.version       # Immutable version tracking
apiclient get security.fips-mode   # FIPS compliance status

# Integration with AWS security services
# ✅ CloudWatch for system metrics
# ✅ Systems Manager for compliance
# ✅ GuardDuty for threat detection
```

## Threat Model Analysis

### Common Container Security Threats

| Threat Vector | AL2/AL2023 Risk | Bottlerocket FIPS Risk |
|---------------|-----------------|------------------------|
| **Container Escape** | High - Many services to exploit | Low - Minimal services |
| **Privilege Escalation** | High - Complex system | Low - Hardened, minimal |
| **Persistent Backdoors** | High - Mutable filesystem | Very Low - Immutable |
| **Package Tampering** | High - Package manager present | None - No package manager |
| **SSH Compromise** | High - SSH enabled | None - No SSH access |
| **Cryptographic Attacks** | Medium - Standard crypto | Very Low - FIPS validated |

### Real-World Security Scenarios

**Scenario 1: Container Breakout Attempt**
```bash
# Attacker gains container access and tries to escalate

# On AL2/AL2023:
attacker@container:$ ls /usr/bin/     # 500+ binaries available
attacker@container:$ sudo su -        # Multiple escalation paths
attacker@container:$ yum install tool # Can install malicious packages

# On Bottlerocket:
attacker@container:$ ls /usr/bin/     # <50 essential binaries only
attacker@container:$ sudo su -        # Limited system access
attacker@container:$ yum install      # Command not found
```

**Scenario 2: Persistence Attempt**
```bash
# Attacker tries to maintain access

# On AL2/AL2023:
attacker@host:$ echo "backdoor" >> /etc/bashrc    # ✅ File modified
attacker@host:$ systemctl enable backdoor.service # ✅ Persistence achieved

# On Bottlerocket:
attacker@host:$ echo "backdoor" >> /etc/bashrc    # ❌ Read-only filesystem
attacker@host:$ systemctl enable backdoor         # ❌ Limited systemd access
```

## Compliance and Regulatory Benefits

### FIPS 140-2 Compliance Requirements

**Industries Requiring FIPS:**
- Federal Government
- Defense Contractors
- Financial Services
- Healthcare (HIPAA)
- Critical Infrastructure

**Bottlerocket FIPS Certification:**
```bash
# Validated cryptographic modules
$ apiclient get security.fips-mode
true

# Certified components:
- OpenSSL FIPS Provider (Certificate #4282)
- Linux Kernel Crypto API (Certificate #4283)
- AWS cryptographic libraries
```

### Audit and Compliance Benefits

**Compliance Advantages:**
- ✅ **Minimal Software Inventory**: Easier to audit and certify
- ✅ **Immutable Infrastructure**: Predictable compliance state
- ✅ **Automated Updates**: Consistent security posture
- ✅ **API-Driven**: All changes are logged and auditable

## Performance and Resource Benefits

### Resource Utilization

| Metric | AL2/AL2023 | Bottlerocket FIPS |
|--------|------------|-------------------|
| **Boot Time** | 30-60 seconds | 10-20 seconds |
| **Memory Footprint** | 500-800 MB | 150-300 MB |
| **Disk Usage** | 2-4 GB | 500 MB - 1 GB |
| **CPU Overhead** | 5-10% | 1-3% |

### Container Performance

```bash
# More resources available for workloads
Available Memory: AL2 (7.2GB) vs Bottlerocket (7.8GB) on 8GB instance
Available CPU: AL2 (90-95%) vs Bottlerocket (97-99%) for containers
Disk I/O: Reduced contention from system services
```

## Implementation Strategy

### EKS Node Group Configuration

```hcl
# Bottlerocket FIPS node group
resource "aws_eks_node_group" "bottlerocket_fips" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "bottlerocket-fips-nodes"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = var.private_subnets
  
  # Bottlerocket FIPS AMI
  ami_type       = "BOTTLEROCKET_x86_64_FIPS"
  capacity_type  = "ON_DEMAND"
  instance_types = ["m5.large", "m5.xlarge"]
  
  # Security-focused configuration
  remote_access {
    ec2_ssh_key = null  # No SSH access
  }
  
  # Immutable updates
  update_config {
    max_unavailable_percentage = 25
  }
  
  tags = {
    Security     = "FIPS-Compliant"
    OS          = "Bottlerocket"
    Compliance  = "FedRAMP-Ready"
  }
}
```

### Security Configuration

```bash
# Bottlerocket configuration via user data
[settings.kubernetes]
cluster-name = "production-cluster"

[settings.kernel]
lockdown = "integrity"  # Enhanced kernel security

[settings.security]
fips-mode = true       # Enable FIPS 140-2 mode

[settings.network]
https-proxy = "https://corporate-proxy:8080"  # Corporate security
```

## Migration Considerations

### From AL2/AL2023 to Bottlerocket

**Migration Benefits:**
- ✅ **Enhanced Security**: Immediate attack surface reduction
- ✅ **Compliance**: FIPS 140-2 certification
- ✅ **Operational Simplicity**: No package management
- ✅ **Performance**: Better resource utilization

**Migration Challenges:**
- 🔄 **Debugging Changes**: No SSH access (use Systems Manager Session Manager)
- 🔄 **Monitoring Adaptation**: Different system metrics
- 🔄 **Tooling Updates**: API-based configuration instead of files

### Operational Adaptations

**Traditional Debugging (AL2/AL2023):**
```bash
# SSH-based troubleshooting
ssh ec2-user@node
sudo journalctl -u kubelet
sudo docker logs container-id
```

**Bottlerocket Debugging:**
```bash
# Systems Manager Session Manager
aws ssm start-session --target i-1234567890abcdef0
apiclient get services.kubelet.enabled
apiclient get logs.kubelet
```

## Cost Implications

### Security ROI Analysis

**Cost Savings:**
- ❌ **Reduced Security Incidents**: Fewer vulnerabilities to exploit
- ❌ **Lower Maintenance**: No package management overhead  
- ❌ **Faster Updates**: Atomic updates reduce maintenance windows
- ❌ **Compliance**: Built-in FIPS compliance reduces audit costs

**Investment Areas:**
- ✅ **Training**: Team adaptation to API-based management
- ✅ **Tooling**: Integration with Bottlerocket APIs
- ✅ **Monitoring**: Adaptation to new metrics and logging

## Conclusion

**Bottlerocket x86_64 FIPS represents a paradigm shift toward security-first container infrastructure**, offering:

### Security Benefits:
1. **90% Attack Surface Reduction**: From 1,000+ to ~50 packages
2. **Immutable Infrastructure**: Cannot be modified at runtime
3. **FIPS 140-2 Compliance**: Government-grade cryptographic security
4. **Zero SSH Attack Vector**: No remote access by default

### Operational Benefits:
1. **Atomic Updates**: All-or-nothing update process
2. **API-Driven Configuration**: Infrastructure as Code friendly
3. **Better Performance**: More resources for workloads
4. **Simplified Management**: No package management complexity

### Compliance Benefits:
1. **Built-in FIPS**: No additional configuration required
2. **Auditable**: Minimal, well-documented software inventory
3. **Predictable**: Immutable infrastructure ensures consistent state

For security-conscious organizations, especially those with compliance requirements, **Bottlerocket FIPS is the clear choice** for container infrastructure.

---

## References

- [AWS Bottlerocket Security Guide](https://github.com/bottlerocket-os/bottlerocket/blob/develop/SECURITY_GUIDANCE.md)
- [FIPS 140-2 Compliance Documentation](https://aws.amazon.com/compliance/fips/)
- [Bottlerocket vs Traditional Linux Comparison](https://aws.amazon.com/bottlerocket/)
- [EKS Security Best Practices](https://aws.github.io/aws-eks-best-practices/security/docs/)
