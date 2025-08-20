# additional-outputs.tf
# Additional outputs for the complete EKS setup

# Node Group Outputs
output "node_group_general_arn" {
  description = "ARN of the general node group"
  value       = aws_eks_node_group.general.arn
}

output "node_group_spot_arn" {
  description = "ARN of the spot node group"
  value       = aws_eks_node_group.spot.arn
}

output "node_group_role_arn" {
  description = "ARN of the node group IAM role"
  value       = aws_iam_role.node_group.arn
}

# Pod Identity Role ARNs
output "vpc_cni_pod_identity_role_arn" {
  description = "ARN of the VPC CNI Pod Identity role"
  value       = aws_iam_role.vpc_cni_pod_identity_role.arn
}

output "ebs_csi_pod_identity_role_arn" {
  description = "ARN of the EBS CSI Pod Identity role"
  value       = aws_iam_role.ebs_csi_pod_identity_role.arn
}

# Access Management Outputs
output "access_entry_arns" {
  description = "Map of principal ARNs to their access entry ARNs"
  value = {
    for arn, entry in local.access_entry_map : arn => "access-entry-${arn}"
  }
  sensitive = true
}

# Kubectl Configuration Command
output "kubectl_config_command" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks_cluster.eks_cluster_id}"
}

# Connection Information
output "cluster_connection_info" {
  description = "Information needed to connect to the cluster"
  value = {
    cluster_name     = module.eks_cluster.eks_cluster_id
    cluster_endpoint = module.eks_cluster.eks_cluster_endpoint
    cluster_region   = var.region
    security_group_id = module.eks_cluster.eks_cluster_managed_security_group_id
    oidc_issuer      = module.eks_cluster.eks_cluster_identity_oidc_issuer
  }
}

# Helm Repository Setup Commands
output "helm_setup_commands" {
  description = "Common Helm repository setup commands for this cluster"
  value = [
    "# AWS Load Balancer Controller",
    "helm repo add eks https://aws.github.io/eks-charts",
    "helm repo update",
    "",
    "# Install AWS Load Balancer Controller (create IAM role first)",
    "helm install aws-load-balancer-controller eks/aws-load-balancer-controller \\",
    "  -n kube-system \\",
    "  --set clusterName=${module.eks_cluster.eks_cluster_id} \\",
    "  --set serviceAccount.create=true \\",
    "  --set serviceAccount.annotations.\"eks\\.amazonaws\\.com/role-arn\"=<LOAD_BALANCER_CONTROLLER_ROLE_ARN>",
    "",
    "# Cluster Autoscaler",
    "helm repo add autoscaler https://kubernetes.github.io/autoscaler",
    "helm repo update",
    "",
    "# Metrics Server (usually pre-installed)",
    "helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/",
    "helm repo update"
  ]
}

# Cluster Validation Commands
output "cluster_validation_commands" {
  description = "Commands to validate cluster setup"
  value = [
    "# Check cluster status",
    "kubectl get nodes -o wide",
    "",
    "# Check system pods",
    "kubectl get pods -n kube-system",
    "",
    "# Check node groups",
    "aws eks describe-nodegroup --cluster-name ${module.eks_cluster.eks_cluster_id} --nodegroup-name ${aws_eks_node_group.general.node_group_name} --region ${var.region}",
    "",
    "# Verify Pod Identity",
    "kubectl get pods -n kube-system -l app=aws-node",
    "kubectl get pods -n kube-system -l app=ebs-csi-controller",
    "",
    "# Test cluster access",
    "kubectl auth can-i '*' '*'",
    "",
    "# Check cluster info",
    "kubectl cluster-info"
  ]
}

# Security Recommendations
output "security_recommendations" {
  description = "Security recommendations for your EKS cluster"
  value = [
    "1. Enable AWS CloudTrail for API logging",
    "2. Set up VPC Flow Logs",
    "3. Configure AWS GuardDuty for threat detection", 
    "4. Implement Network Policies with Calico or Cilium",
    "5. Use Falco for runtime security monitoring",
    "6. Regularly update worker node AMIs",
    "7. Use AWS Secrets Manager or External Secrets Operator",
    "8. Implement Pod Security Standards",
    "9. Enable admission controllers (OPA Gatekeeper)",
    "10. Regular security scanning with tools like kube-bench"
  ]
}

# Cost Optimization Tips
output "cost_optimization_tips" {
  description = "Cost optimization recommendations"
  value = [
    "1. Use Spot instances for non-critical workloads",
    "2. Implement Cluster Autoscaler",
    "3. Use Vertical Pod Autoscaler (VPA)",
    "4. Right-size your nodes based on workload requirements",
    "5. Use Savings Plans or Reserved Instances for stable workloads",
    "6. Enable container insights only if needed",
    "7. Use Fargate for serverless workloads",
    "8. Monitor costs with AWS Cost Explorer",
    "9. Set up billing alerts",
    "10. Use kube-resource-recommender for resource recommendations"
  ]
}
