# EKS Multi-Tenant Namespace Strategy & RBAC Implementation

## Overview

This document outlines the implementation of a secure multi-tenant architecture for our shared EKS cluster using namespace isolation, RBAC, and GitHub OIDC authentication. Each team receives dedicated namespaces with IAM roles that can be assumed from both GitHub Actions (for CI/CD) and AWS Console (for manual operations), while maintaining strict security boundaries through Kubernetes RBAC.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         GitHub Organization                      │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │  Team A     │  │  Team B     │  │  Team C     │            │
│  │  Repository │  │  Repository │  │  Repository │            │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘            │
│         │                 │                 │                    │
│      GitHub            GitHub            GitHub                 │
│      Actions          Actions          Actions                  │
└─────────┴─────────────────┴─────────────────┴──────────────────┘
          │                 │                 │
          │              OIDC Trust           │
          ▼                 ▼                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                        AWS Account                               │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │  Team A     │  │  Team B     │  │  Team C     │            │
│  │  IAM Role   │  │  IAM Role   │  │  IAM Role   │            │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘            │
│         │                 │                 │                    │
│      EKS Access        EKS Access       EKS Access              │
│        Entry             Entry            Entry                  │
└─────────┴─────────────────┴─────────────────┴──────────────────┘
          │                 │                 │
          ▼                 ▼                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Shared EKS Cluster                          │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │  Namespace:  │  │  Namespace:  │  │  Namespace:  │         │
│  │   team-a-*   │  │   team-b-*   │  │   team-c-*   │         │
│  │              │  │              │  │              │         │
│  │  • RBAC      │  │  • RBAC      │  │  • RBAC      │         │
│  │  • Quotas    │  │  • Quotas    │  │  • Quotas    │         │
│  │  • Limits    │  │  • Limits    │  │  • Limits    │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
└─────────────────────────────────────────────────────────────────┘
```

## Implementation Components

### 1. **GitHub OIDC Provider Setup**

First, establish the OIDC trust relationship between GitHub and AWS:

```hcl
# terraform/github-oidc-provider.tf
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
  
  client_id_list = ["sts.amazonaws.com"]
  
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
  
  tags = {
    Name        = "github-actions-oidc"
    Purpose     = "eks-deployment"
    ManagedBy   = "platform-team"
  }
}
```

### 2. **Team IAM Roles with Dual Trust**

Create IAM roles that can be assumed from both GitHub Actions and AWS Console:

```hcl
# terraform/team-iam-roles.tf
locals {
  github_org = "your-org-name"
  account_id = data.aws_caller_identity.current.account_id
}

resource "aws_iam_role" "team_a_eks_access" {
  name = "team-a-eks-namespace-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Trust for GitHub Actions from team repo
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:${local.github_org}/team-a-*:*",
              "repo:${local.github_org}/team-a-app:environment:development",
              "repo:${local.github_org}/team-a-app:environment:staging",
              "repo:${local.github_org}/team-a-app:environment:production"
            ]
          }
        }
      },
      {
        # Trust for AWS Console users (with MFA required)
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          Bool = {
            "aws:MultiFactorAuthPresent" = "true"
          }
          StringEquals = {
            "aws:PrincipalTag/Team" = "team-a"
            "aws:PrincipalTag/Department" = "engineering"
          }
        }
      }
    ]
  })
  
  # Session policy for additional security
  max_session_duration = 3600  # 1 hour
  
  tags = {
    Team        = "team-a"
    Purpose     = "eks-namespace-access"
    GitHubRepo  = "${local.github_org}/team-a-*"
    ManagedBy   = "platform-team"
  }
}

# Attach minimal EKS access policy
resource "aws_iam_role_policy" "team_a_eks_access" {
  name = "eks-cluster-access"
  role = aws_iam_role.team_a_eks_access.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "eks:AccessKubernetesApi"
        ]
        Resource = "arn:aws:eks:${var.region}:${local.account_id}:cluster/${var.cluster_name}"
      }
    ]
  })
}

# Optional: Attach policies for AWS services the team needs
resource "aws_iam_role_policy" "team_a_aws_services" {
  name = "team-a-aws-services"
  role = aws_iam_role.team_a_eks_access.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::team-a-*/*"
        ]
      },
      {
        Sid = "ECRAccess"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = [
          "arn:aws:ecr:${var.region}:${local.account_id}:repository/team-a-*"
        ]
      }
    ]
  })
}
```

### 3. **GitHub Repository Setup**

Configure GitHub environments and secrets:

```yaml
# .github/environments/development/secrets
# Add these as GitHub Environment Secrets
AWS_ROLE_ARN: arn:aws:iam::123456789012:role/team-a-eks-namespace-role
AWS_REGION: us-gov-west-1
EKS_CLUSTER_NAME: shared-eks-cluster
NAMESPACE: team-a-dev
```

GitHub Actions workflow example:

```yaml
# .github/workflows/deploy-to-eks.yml
name: Deploy to EKS

on:
  push:
    branches: [main, develop]
  workflow_dispatch:

permissions:
  id-token: write  # Required for OIDC
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: 
      name: ${{ github.ref == 'refs/heads/main' && 'production' || 'development' }}
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          role-session-name: GitHubActions-${{ github.repository }}-${{ github.run_id }}
          aws-region: ${{ secrets.AWS_REGION }}
      
      - name: Update kubeconfig
        run: |
          aws eks update-kubeconfig \
            --region ${{ secrets.AWS_REGION }} \
            --name ${{ secrets.EKS_CLUSTER_NAME }}
      
      - name: Verify namespace access
        run: |
          # This should work - team has access to their namespace
          kubectl get pods -n ${{ secrets.NAMESPACE }}
          
          # This should fail - no access to other namespaces
          kubectl get pods -n team-b-dev || echo "Expected: Access denied to other team's namespace"
      
      - name: Deploy application
        run: |
          kubectl apply -f k8s/deployment.yaml -n ${{ secrets.NAMESPACE }}
          kubectl rollout status deployment/my-app -n ${{ secrets.NAMESPACE }}
```

### 4. **EKS Access Entries Configuration**

Map the IAM roles to Kubernetes permissions with namespace restrictions:

```hcl
# terraform/eks-access-entries.tf
resource "aws_eks_access_entry" "team_a" {
  cluster_name      = var.cluster_name
  principal_arn     = aws_iam_role.team_a_eks_access.arn
  kubernetes_groups = ["team-a-users"]
  type             = "STANDARD"
  
  tags = {
    Team = "team-a"
  }
}

# Development namespace access
resource "aws_eks_access_policy_association" "team_a_dev" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.team_a_eks_access.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
  
  access_scope {
    type       = "namespace"
    namespaces = ["team-a-dev"]
  }
}

# Staging namespace access (more restricted)
resource "aws_eks_access_policy_association" "team_a_staging" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.team_a_eks_access.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  
  access_scope {
    type       = "namespace"
    namespaces = ["team-a-staging"]
  }
}

# Production namespace access (view only by default)
resource "aws_eks_access_policy_association" "team_a_prod" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.team_a_eks_access.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  
  access_scope {
    type       = "namespace"
    namespaces = ["team-a-prod"]
  }
}
```

### 5. **Kubernetes RBAC for Fine-Grained Control**

Define specific permissions within namespaces:

```yaml
# k8s/rbac/team-a-rbac.yaml
---
# Development environment - full access
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: team-a-developer
  namespace: team-a-dev
rules:
  # Deployment management
  - apiGroups: ["apps", ""]
    resources: ["deployments", "replicasets", "pods", "pods/log", "pods/exec", "pods/portforward"]
    verbs: ["*"]
  
  # Service and networking
  - apiGroups: ["", "networking.k8s.io"]
    resources: ["services", "endpoints", "ingresses"]
    verbs: ["*"]
  
  # Configuration
  - apiGroups: [""]
    resources: ["configmaps", "secrets", "serviceaccounts"]
    verbs: ["*"]
  
  # Autoscaling
  - apiGroups: ["autoscaling"]
    resources: ["horizontalpodautoscalers"]
    verbs: ["*"]
  
  # Jobs
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["*"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-a-developer-binding
  namespace: team-a-dev
subjects:
  - kind: Group
    name: team-a-users
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: team-a-developer
  apiGroup: rbac.authorization.k8s.io

---
# Production environment - restricted access
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: team-a-prod-deployer
  namespace: team-a-prod
rules:
  # Can update deployments but not delete
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets"]
    verbs: ["get", "list", "watch", "update", "patch"]
  
  # Can view but not modify services
  - apiGroups: [""]
    resources: ["services", "endpoints", "pods", "pods/log"]
    verbs: ["get", "list", "watch"]
  
  # Can update specific configmaps/secrets
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["get", "list", "watch"]
    resourceNames: ["app-config", "app-secrets"]  # Only specific resources
  
  # Can scale but not delete
  - apiGroups: ["autoscaling"]
    resources: ["horizontalpodautoscalers"]
    verbs: ["get", "list", "update", "patch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-a-prod-deployer-binding
  namespace: team-a-prod
subjects:
  - kind: Group
    name: team-a-users
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: team-a-prod-deployer
  apiGroup: rbac.authorization.k8s.io
```

### 6. **Resource Quotas and Limits**

Prevent resource overconsumption:

```yaml
# k8s/resource-management/team-a-quotas.yaml
---
# Development - moderate limits
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-a-dev-quota
  namespace: team-a-dev
spec:
  hard:
    requests.cpu: "10"
    requests.memory: "20Gi"
    limits.cpu: "20"
    limits.memory: "40Gi"
    persistentvolumeclaims: "5"
    services.loadbalancers: "1"
    pods: "50"

---
# Production - higher limits
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-a-prod-quota
  namespace: team-a-prod
spec:
  hard:
    requests.cpu: "50"
    requests.memory: "100Gi"
    limits.cpu: "100"
    limits.memory: "200Gi"
    persistentvolumeclaims: "20"
    services.loadbalancers: "3"
    pods: "200"

---
# LimitRange for pod defaults
apiVersion: v1
kind: LimitRange
metadata:
  name: team-a-dev-limits
  namespace: team-a-dev
spec:
  limits:
  - type: Container
    default:
      cpu: "1"
      memory: "1Gi"
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
    max:
      cpu: "2"
      memory: "4Gi"
    min:
      cpu: "50m"
      memory: "64Mi"
  - type: Pod
    max:
      cpu: "8"
      memory: "16Gi"
```

### 7. **Network Policies (Optional)**

Isolate namespace traffic:

```yaml
# k8s/network-policies/team-a-network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: team-a-network-policy
  namespace: team-a-dev
spec:
  podSelector: {}  # Apply to all pods in namespace
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Allow traffic from same namespace
  - from:
    - podSelector: {}
  # Allow traffic from ingress controller
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
  egress:
  # Allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    - podSelector:
        matchLabels:
          k8s-app: kube-dns
  # Allow traffic within namespace
  - to:
    - podSelector: {}
  # Allow external traffic (can be restricted further)
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
```

## Console Access for Teams

Team members can access their namespaces via AWS Console:

1. **Assume the team role** via AWS Console:
   - Switch Role → Enter account ID and role name
   - MFA will be required (enforced by trust policy)

2. **Access EKS cluster**:
   ```bash
   # After assuming role in console or CLI
   aws eks update-kubeconfig --region us-gov-west-1 --name shared-eks-cluster
   
   # Verify access
   kubectl get pods -n team-a-dev  # ✓ Works
   kubectl get pods -n team-b-dev  # ✗ Access denied
   ```

## Security Considerations

### What Teams CAN Do:
- ✅ Deploy applications to their assigned namespaces
- ✅ Manage their own ConfigMaps and Secrets
- ✅ Scale their deployments within resource quotas
- ✅ View logs and exec into their own pods
- ✅ Create services and ingresses in their namespaces

### What Teams CANNOT Do:
- ❌ Access other teams' namespaces
- ❌ Exceed resource quotas
- ❌ Create cluster-wide resources
- ❌ Modify RBAC policies
- ❌ Access the underlying nodes
- ❌ Deploy privileged containers (blocked by PSP/PSS)

## Monitoring and Compliance

### Audit Logging
```bash
# View authentication attempts
aws eks describe-audit-configuration --cluster-name shared-eks-cluster

# Check CloudTrail for AssumeRole events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-items 10
```

### Resource Usage Monitoring
```bash
# Check quota usage
kubectl describe resourcequota -n team-a-dev

# View current resource consumption
kubectl top pods -n team-a-dev
kubectl top nodes
```

## Onboarding New Teams

1. **Create GitHub Repository**:
   ```bash
   gh repo create ${GITHUB_ORG}/team-${TEAM_NAME}-app --private
   ```

2. **Provision IAM Role**:
   ```bash
   terraform apply -var="team_name=${TEAM_NAME}"
   ```

3. **Create Namespaces**:
   ```bash
   kubectl apply -f namespaces/team-${TEAM_NAME}-namespaces.yaml
   ```

4. **Configure EKS Access**:
   ```bash
   aws eks create-access-entry \
     --cluster-name shared-eks-cluster \
     --principal-arn arn:aws:iam::${ACCOUNT_ID}:role/team-${TEAM_NAME}-eks-namespace-role
   ```

5. **Apply RBAC and Quotas**:
   ```bash
   kubectl apply -f rbac/team-${TEAM_NAME}-rbac.yaml
   kubectl apply -f resource-management/team-${TEAM_NAME}-quotas.yaml
   ```

6. **Configure GitHub Secrets**:
   ```bash
   gh secret set AWS_ROLE_ARN \
     --env development \
     --repo ${GITHUB_ORG}/team-${TEAM_NAME}-app \
     --body "arn:aws:iam::${ACCOUNT_ID}:role/team-${TEAM_NAME}-eks-namespace-role"
   ```

## Troubleshooting

### Common Issues

**1. GitHub Actions authentication failures:**
```bash
# Verify OIDC provider thumbprint
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com
```

**2. Namespace access denied:**
```bash
# Check EKS access entry
aws eks describe-access-entry \
  --cluster-name shared-eks-cluster \
  --principal-arn ${ROLE_ARN}

# Verify RBAC bindings
kubectl get rolebindings -n ${NAMESPACE} -o yaml
```

**3. Resource quota exceeded:**
```bash
# Check current usage vs limits
kubectl describe resourcequota -n ${NAMESPACE}
kubectl get pods -n ${NAMESPACE} --field-selector=status.phase=Pending
```

## References

- [EKS Access Management](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)
- [GitHub OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
