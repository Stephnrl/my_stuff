# variables.tf

variable "cluster_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "region" {
  type = string
}

variable "lb_controller_chart_version" {
  type    = string
  default = "1.7.1"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets for internal ALB placement"
}
