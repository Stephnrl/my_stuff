# AWS Security Group Terraform Module Structure

## Directory Structure
```
modules/
├── security-group/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── versions.tf
├── sg-rules/
│   ├── ssh/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── rdp/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── https/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── http/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── eks-node/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── rds-mysql/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── rds-postgres/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── dynamodb/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── redis/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── elasticsearch/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── nfs/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
```

## Main Security Group Module

### modules/security-group/main.tf
```hcl
resource "aws_security_group" "this" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = var.name
    }
  )
}

# Allow all outbound traffic by default
resource "aws_security_group_rule" "egress_all" {
  count = var.create_default_egress ? 1 : 0

  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.this.id
  description       = "Allow all outbound traffic"
}

# Custom ingress rules
resource "aws_security_group_rule" "ingress_rules" {
  for_each = { for rule in var.ingress_rules : rule.key => rule }

  type              = "ingress"
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  protocol          = each.value.protocol
  cidr_blocks       = lookup(each.value, "cidr_blocks", null)
  ipv6_cidr_blocks  = lookup(each.value, "ipv6_cidr_blocks", null)
  security_group_id = aws_security_group.this.id
  description       = lookup(each.value, "description", null)
  source_security_group_id = lookup(each.value, "source_security_group_id", null)
}

# Custom egress rules
resource "aws_security_group_rule" "egress_rules" {
  for_each = { for rule in var.egress_rules : rule.key => rule }

  type              = "egress"
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  protocol          = each.value.protocol
  cidr_blocks       = lookup(each.value, "cidr_blocks", null)
  ipv6_cidr_blocks  = lookup(each.value, "ipv6_cidr_blocks", null)
  security_group_id = aws_security_group.this.id
  description       = lookup(each.value, "description", null)
  target_security_group_id = lookup(each.value, "target_security_group_id", null)
}
```

### modules/security-group/variables.tf
```hcl
variable "name" {
  description = "Name of the security group"
  type        = string
}

variable "description" {
  description = "Description of the security group"
  type        = string
  default     = "Managed by Terraform"
}

variable "vpc_id" {
  description = "VPC ID where the security group will be created"
  type        = string
}

variable "create_default_egress" {
  description = "Whether to create default egress rule allowing all outbound traffic"
  type        = bool
  default     = true
}

variable "ingress_rules" {
  description = "List of ingress rules"
  type = list(object({
    key                      = string
    from_port                = number
    to_port                  = number
    protocol                 = string
    cidr_blocks              = optional(list(string))
    ipv6_cidr_blocks         = optional(list(string))
    source_security_group_id = optional(string)
    description              = optional(string)
  }))
  default = []
}

variable "egress_rules" {
  description = "List of egress rules"
  type = list(object({
    key                      = string
    from_port                = number
    to_port                  = number
    protocol                 = string
    cidr_blocks              = optional(list(string))
    ipv6_cidr_blocks         = optional(list(string))
    target_security_group_id = optional(string)
    description              = optional(string)
  }))
  default = []
}

variable "tags" {
  description = "Tags to apply to the security group"
  type        = map(string)
  default     = {}
}
```

### modules/security-group/outputs.tf
```hcl
output "security_group_id" {
  description = "The ID of the security group"
  value       = aws_security_group.this.id
}

output "security_group_arn" {
  description = "The ARN of the security group"
  value       = aws_security_group.this.arn
}

output "security_group_name" {
  description = "The name of the security group"
  value       = aws_security_group.this.name
}
```

### modules/security-group/versions.tf
```hcl
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}
```

## Rule Modules

### modules/sg-rules/ssh/main.tf
```hcl
locals {
  ssh_rule = {
    key         = "ssh-22"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.cidr_blocks
    description = var.description != "" ? var.description : "SSH access from ${join(", ", var.cidr_blocks)}"
  }
}
```

### modules/sg-rules/ssh/variables.tf
```hcl
variable "cidr_blocks" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "description" {
  description = "Description for the SSH rule"
  type        = string
  default     = ""
}
```

### modules/sg-rules/ssh/outputs.tf
```hcl
output "rule" {
  description = "SSH ingress rule configuration"
  value       = local.ssh_rule
}
```

### modules/sg-rules/rdp/main.tf
```hcl
locals {
  rdp_rule = {
    key         = "rdp-3389"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = var.cidr_blocks
    description = var.description != "" ? var.description : "RDP access from ${join(", ", var.cidr_blocks)}"
  }
}
```

### modules/sg-rules/rdp/variables.tf
```hcl
variable "cidr_blocks" {
  description = "CIDR blocks allowed for RDP access"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "description" {
  description = "Description for the RDP rule"
  type        = string
  default     = ""
}
```

### modules/sg-rules/rdp/outputs.tf
```hcl
output "rule" {
  description = "RDP ingress rule configuration"
  value       = local.rdp_rule
}
```

### modules/sg-rules/https/main.tf
```hcl
locals {
  https_rule = {
    key         = "https-443"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.cidr_blocks
    description = var.description != "" ? var.description : "HTTPS access from ${join(", ", var.cidr_blocks)}"
  }
}
```

### modules/sg-rules/https/variables.tf
```hcl
variable "cidr_blocks" {
  description = "CIDR blocks allowed for HTTPS access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "description" {
  description = "Description for the HTTPS rule"
  type        = string
  default     = ""
}
```

### modules/sg-rules/https/outputs.tf
```hcl
output "rule" {
  description = "HTTPS ingress rule configuration"
  value       = local.https_rule
}
```

### modules/sg-rules/http/main.tf
```hcl
locals {
  http_rule = {
    key         = "http-80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.cidr_blocks
    description = var.description != "" ? var.description : "HTTP access from ${join(", ", var.cidr_blocks)}"
  }
}
```

### modules/sg-rules/eks-node/main.tf
```hcl
locals {
  eks_node_rules = [
    {
      key         = "kubelet-api"
      from_port   = 10250
      to_port     = 10250
      protocol    = "tcp"
      cidr_blocks = var.cluster_cidr_blocks
      description = "Kubelet API"
    },
    {
      key         = "nodeport-services"
      from_port   = 30000
      to_port     = 32767
      protocol    = "tcp"
      cidr_blocks = var.service_cidr_blocks
      description = "NodePort Services"
    },
    {
      key         = "eks-cluster-api"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      source_security_group_id = var.cluster_security_group_id
      description = "Allow pods to communicate with the cluster API"
    }
  ]
}
```

### modules/sg-rules/eks-node/variables.tf
```hcl
variable "cluster_cidr_blocks" {
  description = "CIDR blocks for cluster communication"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "service_cidr_blocks" {
  description = "CIDR blocks for NodePort services"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_security_group_id" {
  description = "EKS cluster security group ID for API communication"
  type        = string
  default     = null
}
```

### modules/sg-rules/eks-node/outputs.tf
```hcl
output "rules" {
  description = "EKS node ingress rules configuration"
  value       = local.eks_node_rules
}
```

### modules/sg-rules/rds-mysql/main.tf
```hcl
locals {
  mysql_rule = {
    key         = "mysql-3306"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = var.cidr_blocks
    source_security_group_id = var.source_security_group_id
    description = var.description != "" ? var.description : "MySQL/Aurora access"
  }
}
```

### modules/sg-rules/rds-postgres/main.tf
```hcl
locals {
  postgres_rule = {
    key         = "postgres-5432"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.cidr_blocks
    source_security_group_id = var.source_security_group_id
    description = var.description != "" ? var.description : "PostgreSQL access"
  }
}
```

### modules/sg-rules/redis/main.tf
```hcl
locals {
  redis_rule = {
    key         = "redis-6379"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = var.cidr_blocks
    source_security_group_id = var.source_security_group_id
    description = var.description != "" ? var.description : "Redis/ElastiCache access"
  }
}
```

### modules/sg-rules/elasticsearch/main.tf
```hcl
locals {
  elasticsearch_rules = [
    {
      key         = "elasticsearch-rest"
      from_port   = 9200
      to_port     = 9200
      protocol    = "tcp"
      cidr_blocks = var.cidr_blocks
      source_security_group_id = var.source_security_group_id
      description = "Elasticsearch REST API"
    },
    {
      key         = "elasticsearch-node"
      from_port   = 9300
      to_port     = 9300
      protocol    = "tcp"
      cidr_blocks = var.cidr_blocks
      source_security_group_id = var.source_security_group_id
      description = "Elasticsearch node communication"
    }
  ]
}
```

### modules/sg-rules/nfs/main.tf
```hcl
locals {
  nfs_rule = {
    key         = "nfs-2049"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = var.cidr_blocks
    source_security_group_id = var.source_security_group_id
    description = var.description != "" ? var.description : "NFS/EFS access"
  }
}
```

## Usage Examples

### Example 1: Basic Web Server Security Group
```hcl
module "ssh_rule" {
  source = "./modules/sg-rules/ssh"
  cidr_blocks = ["10.0.0.0/8"]
}

module "https_rule" {
  source = "./modules/sg-rules/https"
  cidr_blocks = ["0.0.0.0/0"]
}

module "http_rule" {
  source = "./modules/sg-rules/http"
  cidr_blocks = ["0.0.0.0/0"]
}

module "web_server_sg" {
  source = "./modules/security-group"
  
  name        = "web-server-sg"
  description = "Security group for web servers"
  vpc_id      = var.vpc_id
  
  ingress_rules = [
    module.ssh_rule.rule,
    module.https_rule.rule,
    module.http_rule.rule
  ]
  
  tags = {
    Environment = "production"
    Service     = "web"
  }
}
```

### Example 2: EKS Node Group Security Group
```hcl
module "ssh_rule" {
  source = "./modules/sg-rules/ssh"
  cidr_blocks = ["10.0.0.0/16"]
}

module "eks_node_rules" {
  source = "./modules/sg-rules/eks-node"
  cluster_cidr_blocks = ["10.0.0.0/16"]
  cluster_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

module "eks_node_sg" {
  source = "./modules/security-group"
  
  name        = "eks-node-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id
  
  ingress_rules = concat(
    [module.ssh_rule.rule],
    module.eks_node_rules.rules
  )
  
  tags = {
    Environment = "production"
    Service     = "eks-nodes"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}
```

### Example 3: RDS Database Security Group
```hcl
module "mysql_rule" {
  source = "./modules/sg-rules/rds-mysql"
  source_security_group_id = module.app_sg.security_group_id
}

module "rds_sg" {
  source = "./modules/security-group"
  
  name        = "rds-mysql-sg"
  description = "Security group for RDS MySQL database"
  vpc_id      = var.vpc_id
  
  ingress_rules = [
    module.mysql_rule.rule
  ]
  
  tags = {
    Environment = "production"
    Service     = "database"
  }
}
```

### Example 4: Multi-Service Application Stack
```hcl
# Application server security group
module "app_sg" {
  source = "./modules/security-group"
  
  name        = "app-server-sg"
  description = "Security group for application servers"
  vpc_id      = var.vpc_id
  
  ingress_rules = [
    {
      key         = "alb-traffic"
      from_port   = 8080
      to_port     = 8080
      protocol    = "tcp"
      source_security_group_id = module.alb_sg.security_group_id
      description = "Traffic from ALB"
    }
  ]
}

# Redis cache security group
module "redis_rule" {
  source = "./modules/sg-rules/redis"
  source_security_group_id = module.app_sg.security_group_id
}

module "redis_sg" {
  source = "./modules/security-group"
  
  name        = "redis-cache-sg"
  description = "Security group for Redis cache"
  vpc_id      = var.vpc_id
  
  ingress_rules = [
    module.redis_rule.rule
  ]
}

# Database security group
module "postgres_rule" {
  source = "./modules/sg-rules/rds-postgres"
  source_security_group_id = module.app_sg.security_group_id
}

module "database_sg" {
  source = "./modules/security-group"
  
  name        = "postgres-db-sg"
  description = "Security group for PostgreSQL database"
  vpc_id      = var.vpc_id
  
  ingress_rules = [
    module.postgres_rule.rule
  ]
}
```

## Additional Service Modules You Can Add

### modules/sg-rules/memcached/main.tf
```hcl
locals {
  memcached_rule = {
    key         = "memcached-11211"
    from_port   = 11211
    to_port     = 11211
    protocol    = "tcp"
    cidr_blocks = var.cidr_blocks
    source_security_group_id = var.source_security_group_id
    description = "Memcached access"
  }
}
```

### modules/sg-rules/mongodb/main.tf
```hcl
locals {
  mongodb_rule = {
    key         = "mongodb-27017"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = var.cidr_blocks
    source_security_group_id = var.source_security_group_id
    description = "MongoDB access"
  }
}
```

### modules/sg-rules/kafka/main.tf
```hcl
locals {
  kafka_rules = [
    {
      key         = "kafka-broker"
      from_port   = 9092
      to_port     = 9092
      protocol    = "tcp"
      cidr_blocks = var.cidr_blocks
      description = "Kafka broker"
    },
    {
      key         = "kafka-zookeeper"
      from_port   = 2181
      to_port     = 2181
      protocol    = "tcp"
      cidr_blocks = var.cidr_blocks
      description = "Zookeeper"
    }
  ]
}
```

### modules/sg-rules/grafana/main.tf
```hcl
locals {
  grafana_rule = {
    key         = "grafana-3000"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.cidr_blocks
    description = "Grafana dashboard access"
  }
}
```

### modules/sg-rules/prometheus/main.tf
```hcl
locals {
  prometheus_rule = {
    key         = "prometheus-9090"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.cidr_blocks
    description = "Prometheus metrics"
  }
}
```

## Tips for Usage

1. **Composition Pattern**: Mix and match rule modules to create security groups for different use cases.

2. **Environment-Specific CIDRs**: Override default CIDR blocks per environment:
```hcl
module "ssh_rule" {
  source = "./modules/sg-rules/ssh"
  cidr_blocks = var.environment == "prod" ? ["10.0.0.0/8"] : ["0.0.0.0/0"]
}
```

3. **Security Group References**: Use `source_security_group_id` for service-to-service communication instead of CIDR blocks when possible.

4. **Reusable Variables**: Create a common variables file for frequently used values:
```hcl
locals {
  vpc_cidr = "10.0.0.0/16"
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24"]
}
```

5. **Tagging Strategy**: Use consistent tags across all security groups for cost tracking and compliance.
