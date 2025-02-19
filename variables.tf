variable "vpc_count" {
  description = "Number of VPCs to create"
  type        = number
  default     = 1
}

variable "vpc_cidr_blocks" {
  description = "List of CIDR blocks for each VPC"
  type        = list(string)
  default     = ["10.0.0.0/16", "10.1.0.0/16"]
}

variable "region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = "us-west-2"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
  default     = "multi-vpc-project"
}
