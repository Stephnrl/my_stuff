EKS Pod Identity (New) vs IRSA (Old Way)
Let me break down both approaches and why Pod Identity is particularly beneficial for your private networking setup.
IRSA (The Old Way - since 2019)
How IRSA Works:
yaml# Complex flow requiring public OIDC endpoint
1. Pod starts with ServiceAccount
2. ServiceAccount has annotation: eks.amazonaws.com/role-arn
3. Webhook mutates pod → injects AWS_WEB_IDENTITY_TOKEN_FILE
4. Pod reads projected token from filesystem
5. Pod calls PUBLIC OIDC endpoint for validation
6. STS AssumeRoleWithWebIdentity using token
7. Pod gets temporary AWS credentials
IRSA Pain Points:

Requires public OIDC endpoint (your exact problem!)
Complex setup with multiple components
Must create IAM OIDC provider in each AWS account
Trust policy gets messy with multiple clusters
Token expires every 24 hours (pod restart issues)

IRSA Architecture:
bashPod → Public Internet → oidc.eks.region.amazonaws.com (MUST be public)
    → STS endpoint → AssumeRoleWithWebIdentity
EKS Pod Identity (New Way - GA in late 2023)
How Pod Identity Works:
yaml# Simplified flow - NO public endpoints needed!
1. Pod starts with ServiceAccount
2. Pod Identity Association links ServiceAccount → IAM Role
3. EKS Pod Identity Agent (add-on) runs as DaemonSet
4. Agent intercepts IMDS calls from pod
5. Agent talks to EKS Auth API (private)
6. Returns temporary credentials directly
7. NO OIDC endpoint needed at all!
Pod Identity Benefits:
yaml✅ No public OIDC endpoint required
✅ Works entirely with private endpoints
✅ Simpler IAM trust policies
✅ No OIDC provider setup needed
✅ Credentials refresh automatically
✅ Cross-account roles easier
✅ Faster pod startup times
Setup Comparison
IRSA Setup (Old):
bash# 1. Create OIDC Provider (per cluster, per account!)
aws iam create-open-id-connect-provider \
  --url https://oidc.eks.region.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE

# 2. Create IAM Role with complex trust policy
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/oidc.eks.region.amazonaws.com/id/XXX"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.region.amazonaws.com/id/XXX:sub": "system:serviceaccount:NAMESPACE:SA-NAME",
        "oidc.eks.region.amazonaws.com/id/XXX:aud": "sts.amazonaws.com"
      }
    }
  }]
}

# 3. Annotate ServiceAccount
kubectl annotate serviceaccount my-sa \
  eks.amazonaws.com/role-arn=arn:aws:iam::ACCOUNT:role/my-role
Pod Identity Setup (New):
bash# 1. Install EKS Pod Identity Agent add-on
aws eks create-addon --cluster-name my-cluster \
  --addon-name eks-pod-identity-agent

# 2. Create IAM Role with SIMPLE trust policy
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": "pods.eks.amazonaws.com"
    },
    "Action": ["sts:AssumeRole", "sts:TagSession"]
  }]
}

# 3. Create Pod Identity Association
aws eks create-pod-identity-association \
  --cluster-name my-cluster \
  --namespace my-namespace \
  --service-account my-sa \
  --role-arn arn:aws:iam::ACCOUNT:role/my-role
For Your Private Network Setup
Why Pod Identity is Perfect for You:
yamlYour Current Challenge with IRSA:
  On-Prem → VPN → TGW → EKS VPC → ??? → Public OIDC Endpoint
                                    ↑
                              (Requires Internet or Proxy)

With Pod Identity:
  On-Prem → VPN → TGW → EKS VPC → EKS Auth API (Private!)
                                    ↑
                              (No Internet needed!)
Network Requirements:
IRSA Requirements:

Public OIDC endpoint access (internet or proxy)
VPC Endpoint for STS
Complex DNS/proxy setup for private access

Pod Identity Requirements:

EKS Pod Identity Agent add-on
VPC Endpoint for STS (optional but recommended)
Works with private-only clusters out of the box!
