{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EKSClusterReadAccess",
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters",
        "eks:DescribeNodegroup",
        "eks:ListNodegroups",
        "eks:DescribeAddon",
        "eks:ListAddons",
        "eks:DescribeUpdate",
        "eks:ListUpdates"
      ],
      "Resource": [
        "arn:aws:eks:${region}:${account_id}:cluster/${cluster_name}",
        "arn:aws:eks:${region}:${account_id}:nodegroup/${cluster_name}/*/*",
        "arn:aws:eks:${region}:${account_id}:addon/${cluster_name}/*/*"
      ]
    },
    {
      "Sid": "EKSKubernetesAPIAccess",
      "Effect": "Allow",
      "Action": [
        "eks:AccessKubernetesApi"
      ],
      "Resource": "arn:aws:eks:${region}:${account_id}:cluster/${cluster_name}",
      "Condition": {
        "StringEquals": {
          "kubernetes.io/namespace": [
%{ for namespace in namespaces ~}
            "${namespace}"${length(namespaces) > 1 && namespace != namespaces[length(namespaces)-1] ? "," : ""}
%{ endfor ~}
          ]
        }
      }
    },
    {
      "Sid": "ECRRepositoryAccess",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:DescribeImages",
        "ecr:ListImages",
        "ecr:DescribeRepositories",
        "ecr:GetRepositoryPolicy"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ECRImagePushPull",
      "Effect": "Allow",
      "Action": [
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:BatchDeleteImage"
      ],
      "Resource": [
%{ for repo in ecr_repositories ~}
        "arn:aws:ecr:${region}:${account_id}:repository/${repo}"${length(ecr_repositories) > 1 && repo != ecr_repositories[length(ecr_repositories)-1] ? "," : ""}
%{ endfor ~}
      ]
    },
    {
      "Sid": "S3ArtifactsAccess",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketVersioning"
      ],
      "Resource": [
%{ for bucket in s3_buckets ~}
        "arn:aws:s3:::${bucket}"${length(s3_buckets) > 1 && bucket != s3_buckets[length(s3_buckets)-1] ? "," : ""}
%{ endfor ~}
      ]
    },
    {
      "Sid": "S3ObjectAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:GetObjectVersion",
        "s3:PutObjectAcl",
        "s3:GetObjectAcl"
      ],
      "Resource": [
%{ for bucket in s3_buckets ~}
        "arn:aws:s3:::${bucket}/*"${length(s3_buckets) > 1 && bucket != s3_buckets[length(s3_buckets)-1] ? "," : ""}
%{ endfor ~}
      ]
    },
    {
      "Sid": "CloudWatchLogsAccess",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:FilterLogEvents",
        "logs:GetLogEvents"
      ],
      "Resource": [
        "arn:aws:logs:${region}:${account_id}:log-group:/aws/eks/${cluster_name}/*",
        "arn:aws:logs:${region}:${account_id}:log-group:/aws/containerinsights/${cluster_name}/*",
%{ for namespace in namespaces ~}
        "arn:aws:logs:${region}:${account_id}:log-group:/kubernetes/${namespace}/*"${length(namespaces) > 1 && namespace != namespaces[length(namespaces)-1] ? "," : ""}
%{ endfor ~}
      ]
    },
    {
      "Sid": "SecretsManagerAccess",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": [
%{ for namespace in namespaces ~}
        "arn:aws:secretsmanager:${region}:${account_id}:secret:${namespace}/*"${length(namespaces) > 1 && namespace != namespaces[length(namespaces)-1] ? "," : ""}
%{ endfor ~}
      ]
    },
    {
      "Sid": "ParameterStoreAccess",
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath",
        "ssm:DescribeParameters"
      ],
      "Resource": [
%{ for namespace in namespaces ~}
        "arn:aws:ssm:${region}:${account_id}:parameter/${namespace}/*"${length(namespaces) > 1 && namespace != namespaces[length(namespaces)-1] ? "," : ""}
%{ endfor ~}
      ]
    },
    {
      "Sid": "AssumeServiceLinkedRoles",
      "Effect": "Allow",
      "Action": [
        "iam:CreateServiceLinkedRole"
      ],
      "Resource": [
        "arn:aws:iam::${account_id}:role/aws-service-role/elasticloadbalancing.amazonaws.com/AWSServiceRoleForElasticLoadBalancing"
      ],
      "Condition": {
        "StringEquals": {
          "iam:AWSServiceName": "elasticloadbalancing.amazonaws.com"
        }
      }
    },
    {
      "Sid": "LoadBalancerAccess",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeLoadBalancerAttributes",
        "elasticloadbalancing:DescribeListeners",
        "elasticloadbalancing:DescribeListenerCertificates",
        "elasticloadbalancing:DescribeSSLPolicies",
        "elasticloadbalancing:DescribeRules",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeTargetGroupAttributes",
        "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:DescribeTags",
        "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:DeleteListener",
        "elasticloadbalancing:CreateRule",
        "elasticloadbalancing:DeleteRule",
        "elasticloadbalancing:ModifyListener",
        "elasticloadbalancing:ModifyRule",
        "elasticloadbalancing:SetRulePriorities",
        "elasticloadbalancing:CreateTargetGroup",
        "elasticloadbalancing:DeleteTargetGroup",
        "elasticloadbalancing:ModifyTargetGroup",
        "elasticloadbalancing:ModifyTargetGroupAttributes",
        "elasticloadbalancing:RegisterTargets",
        "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:AddTags",
        "elasticloadbalancing:RemoveTags"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "${region}"
        }
      }
    },
    {
      "Sid": "Route53Access",
      "Effect": "Allow",
      "Action": [
        "route53:GetChange",
        "route53:GetHostedZone",
        "route53:ListHostedZones",
        "route53:ListHostedZonesByName",
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets",
        "route53:GetHealthCheck",
        "route53:CreateHealthCheck",
        "route53:DeleteHealthCheck",
        "route53:UpdateHealthCheck"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "route53:HostedZoneId": [
%{ for domain in allowed_domains ~}
            "${domain}"${length(allowed_domains) > 1 && domain != allowed_domains[length(allowed_domains)-1] ? "," : ""}
%{ endfor ~}
          ]
        }
      }
    },
    {
      "Sid": "ACMCertificateAccess",
      "Effect": "Allow",
      "Action": [
        "acm:ListCertificates",
        "acm:DescribeCertificate",
        "acm:GetCertificate"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "${region}"
        }
      }
    },
    {
      "Sid": "ServiceDiscoveryAccess",
      "Effect": "Allow",
      "Action": [
        "servicediscovery:GetService",
        "servicediscovery:GetNamespace",
        "servicediscovery:ListServices",
        "servicediscovery:ListNamespaces",
        "servicediscovery:CreateService",
        "servicediscovery:DeleteService",
        "servicediscovery:RegisterInstance",
        "servicediscovery:DeregisterInstance",
        "servicediscovery:ListInstances",
        "servicediscovery:GetInstance",
        "servicediscovery:GetInstancesHealthStatus"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "${region}"
        }
      }
    },
    {
      "Sid": "AutoScalingReadAccess",
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeLaunchTemplates"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2ReadOnlyForEKS",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeInstanceAttribute",
        "ec2:DescribeRegions",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeSubnets",
        "ec2:DescribeVpcs",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeRouteTables",
        "ec2:DescribeInternetGateways",
        "ec2:DescribeNatGateways",
        "ec2:DescribeAddresses",
        "ec2:DescribeTags"
      ],
      "Resource": "*"
    },
%{ if enable_monitoring ~}
    {
      "Sid": "CloudWatchMetricsAccess",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:DeleteAlarms"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "cloudwatch:namespace": [
%{ for namespace in namespaces ~}
            "Kubernetes/${namespace}"${length(namespaces) > 1 && namespace != namespaces[length(namespaces)-1] ? "," : ""}
%{ endfor ~}
          ]
        }
      }
    },
%{ endif ~}
    {
      "Sid": "DenyInfrastructureCreation",
      "Effect": "Deny",
      "Action": [
        "ec2:CreateVpc",
        "ec2:DeleteVpc",
        "ec2:ModifyVpcAttribute",
        "ec2:CreateSubnet",
        "ec2:DeleteSubnet",
        "ec2:ModifySubnetAttribute",
        "ec2:CreateInternetGateway",
        "ec2:DeleteInternetGateway",
        "ec2:AttachInternetGateway",
        "ec2:DetachInternetGateway",
        "ec2:CreateNatGateway",
        "ec2:DeleteNatGateway",
        "ec2:CreateRouteTable",
        "ec2:DeleteRouteTable",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:ReplaceRoute",
        "ec2:AssociateRouteTable",
        "ec2:DisassociateRouteTable",
        "ec2:CreateNetworkAcl",
        "ec2:DeleteNetworkAcl",
        "ec2:CreateVpcEndpoint",
        "ec2:DeleteVpcEndpoint",
        "ec2:CreateVpcPeeringConnection",
        "ec2:DeleteVpcPeeringConnection",
        "ec2:AcceptVpcPeeringConnection",
        "ec2:RejectVpcPeeringConnection"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyEC2InstanceManagement",
      "Effect": "Deny",
      "Action": [
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:StopInstances",
        "ec2:StartInstances",
        "ec2:RebootInstances",
        "ec2:CreateImage",
        "ec2:DeregisterImage",
        "ec2:CreateSnapshot",
        "ec2:DeleteSnapshot",
        "ec2:CreateVolume",
        "ec2:DeleteVolume",
        "ec2:AttachVolume",
        "ec2:DetachVolume",
        "ec2:ModifyInstanceAttribute",
        "ec2:CreateLaunchTemplate",
        "ec2:DeleteLaunchTemplate",
        "ec2:ModifyLaunchTemplate"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyEKSClusterManagement",
      "Effect": "Deny",
      "Action": [
        "eks:CreateCluster",
        "eks:DeleteCluster",
        "eks:UpdateClusterConfig",
        "eks:UpdateClusterVersion",
        "eks:CreateNodegroup",
        "eks:DeleteNodegroup",
        "eks:UpdateNodegroupConfig",
        "eks:UpdateNodegroupVersion",
        "eks:CreateAddon",
        "eks:DeleteAddon",
        "eks:UpdateAddon",
        "eks:CreateAccessEntry",
        "eks:DeleteAccessEntry",
        "eks:UpdateAccessEntry",
        "eks:AssociateAccessPolicy",
        "eks:DisassociateAccessPolicy"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyECRRepositoryManagement",
      "Effect": "Deny",
      "Action": [
        "ecr:CreateRepository",
        "ecr:DeleteRepository",
        "ecr:PutRepositoryPolicy",
        "ecr:DeleteRepositoryPolicy",
        "ecr:SetRepositoryPolicy",
        "ecr:PutLifecyclePolicy",
        "ecr:DeleteLifecyclePolicy",
        "ecr:PutImageTagMutability",
        "ecr:PutImageScanningConfiguration",
        "ecr:PutRegistryPolicy",
        "ecr:DeleteRegistryPolicy"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenySecurityGroupManagement",
      "Effect": "Deny",
      "Action": [
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:ModifySecurityGroupRules"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyIAMChanges",
      "Effect": "Deny",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:UpdateRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:CreateUser",
        "iam:DeleteUser",
        "iam:CreateGroup",
        "iam:DeleteGroup",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:PrincipalServiceName": [
            "eks.amazonaws.com",
            "elasticloadbalancing.amazonaws.com"
          ]
        }
      }
    },
    {
      "Sid": "DenyS3BucketManagement",
      "Effect": "Deny",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:PutBucketPolicy",
        "s3:DeleteBucketPolicy",
        "s3:PutBucketAcl",
        "s3:PutBucketVersioning",
        "s3:PutBucketEncryption",
        "s3:PutBucketLogging",
        "s3:PutBucketNotification",
        "s3:PutBucketCors",
        "s3:PutBucketWebsite",
        "s3:PutBucketReplication"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyRDSManagement",
      "Effect": "Deny",
      "Action": [
        "rds:CreateDBInstance",
        "rds:DeleteDBInstance",
        "rds:CreateDBCluster",
        "rds:DeleteDBCluster",
        "rds:CreateDBSubnetGroup",
        "rds:DeleteDBSubnetGroup",
        "rds:CreateDBParameterGroup",
        "rds:DeleteDBParameterGroup",
        "rds:CreateDBClusterParameterGroup",
        "rds:DeleteDBClusterParameterGroup"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyLoadBalancerCreation",
      "Effect": "Deny",
      "Action": [
        "elasticloadbalancing:CreateLoadBalancer",
        "elasticloadbalancing:DeleteLoadBalancer"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyRoute53HostedZoneManagement",
      "Effect": "Deny",
      "Action": [
        "route53:CreateHostedZone",
        "route53:DeleteHostedZone",
        "route53:UpdateHostedZoneComment"
      ],
      "Resource": "*"
    }
  ]
}
