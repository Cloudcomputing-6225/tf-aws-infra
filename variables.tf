variable "AWS_PROFILE" {
  default = "dev"
}

variable "AWS_REGION" {
  default = "us-east-1"
}

variable "vpc_cidr_block" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
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

variable "db_instance_class" {
  default = "db.t3.micro"
}

variable "DB_NAME" {
  type    = string
  default = "healthchecksdb"
}

variable "DB_USER" {
  type    = string
  default = "sneha"
}

variable "DB_PASS" {
  type      = string
  sensitive = true
  default   = "user3939"
}

variable "S3_BUCKET_NAME" {
  default = "snehacsye6225"
}

variable "security_group_name" {
  default = "webapp-sg"
}

variable "vpc_count" {
  default = 1
}

variable "vpc_cidr_blocks" {
  type    = list(string)
  default = ["10.0.0.0/16"]
}

variable "domain_name" {
  description = "The base domain name (e.g., snehaalluri.me)"
  type        = string
}

variable "subdomain_name" {
  description = "The base domain name (e.g., snehaalluri.me)"
  type        = string
}

variable "route53_zone_id" {
  description = "The Route 53 Hosted Zone ID for the domain"
  type        = string
}
variable "ssl_cert_arn" {
  type        = string
  description = "ARN of the ACM SSL certificate"
}
