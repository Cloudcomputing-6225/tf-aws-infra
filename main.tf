provider "aws" {
  region  = var.aws_region
  profile = "dev"
}
data "aws_availability_zones" "available" {}

resource "aws_vpc" "vpc" {
  count = var.vpc_count

  cidr_block           = var.vpc_cidr_blocks[count.index]
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "VPC-${count.index + 1}-${var.project_name}"
  }
}
#public_subnets 
resource "aws_subnet" "public_subnets" {
  count                   = var.vpc_count * 3
  vpc_id                  = aws_vpc.vpc[floor(count.index / 3)].id
  cidr_block              = var.public_subnet_cidrs[floor(count.index / 3)][count.index % 3]
  availability_zone       = element(data.aws_availability_zones.available.names, count.index % 3)
  map_public_ip_on_launch = true

  tags = {
    Name = "Public-Subnet-${count.index + 1}-VPC-${floor(count.index / 3) + 1}"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = var.vpc_count * 3
  vpc_id            = aws_vpc.vpc[floor(count.index / 3)].id
  cidr_block        = var.private_subnet_cidrs[floor(count.index / 3)][count.index % 3]
  availability_zone = element(data.aws_availability_zones.available.names, count.index % 3)

  tags = {
    Name = "Private-Subnet-${count.index + 1}-VPC-${floor(count.index / 3) + 1}"
  }
}

resource "aws_internet_gateway" "igw" {
  count  = var.vpc_count
  vpc_id = aws_vpc.vpc[count.index].id

  tags = {
    Name = "IGW-VPC-${count.index + 1}"
  }
}
resource "aws_security_group" "webapp_sg" {
  count  = var.vpc_count
  vpc_id = aws_vpc.vpc[count.index].id
  name   = "${var.project_name}-security-group-${count.index + 1}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-${count.index + 1}"
  }
}

resource "aws_instance" "webapp" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public_subnets[0].id
  vpc_security_group_ids = [aws_security_group.webapp_sg[0].id]


  user_data = <<-EOF
              #!/bin/bash
              echo "Starting WebApp Setup"
              sudo systemctl restart myapp
              EOF

  tags = {
    Name = "${var.project_name}-ec2-instance"
  }

  depends_on = [
    aws_security_group.webapp_sg,
    aws_internet_gateway.igw
  ]
}
