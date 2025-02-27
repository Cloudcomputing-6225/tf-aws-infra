variable "aws_profile" {
  default = "dev"
}

variable "aws_region" {
  default = "us-east-1"
}

variable "vpc_count" {
  default = 1
}

variable "vpc_cidr_blocks" {
  type    = list(string)
  default = ["10.0.0.0/16"]
}

variable "public_subnet_cidrs" {
  type    = list(list(string))
  default = [["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]]
}

variable "private_subnet_cidrs" {
  type    = list(list(string))
  default = [["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]]
}

variable "security_group_name" {
  default = "webapp-sg"
}

variable "ami_id" {
  default = "ami-0f1618a69a6bfa751"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "key_name" {
  default = "new-key"
}

variable "project_name" {
  default = "webapp"
}
