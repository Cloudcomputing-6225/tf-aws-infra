# Fetch available AWS zones
data "aws_availability_zones" "available" {}

# Create VPC
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Public Subnets
resource "aws_subnet" "public_subnets" {
  count                   = 3
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "Public-Subnet-${count.index + 1}"
  }
}

# Private Subnets (for RDS)
resource "aws_subnet" "private_subnets" {
  count             = 3
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name = "Private-Subnet-${count.index + 1}"
  }
}

# Internet Gateway for Public Subnets
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "IGW"
  }
}

# Route Table for Public Subnets
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "Public Route Table"
  }
}

# Associate Route Table with Public Subnets
resource "aws_route_table_association" "public_subnet_assoc" {
  count          = 3
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# Security Group for WebApp EC2
resource "aws_security_group" "webapp_sg" {
  vpc_id = aws_vpc.vpc.id
  name   = "webapp-security-group"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Only for SSH, consider restricting access
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
    Name = "WebApp Security Group"
  }
}

# Security Group for RDS (only allows traffic from WebApp SG)
resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.webapp_sg.id]
  }


  tags = {
    Name = "RDS Security Group"
  }
}


# Merged IAM Role for EC2 (S3 + CloudWatch)
resource "aws_iam_role" "ec2_combined_role" {
  name = "ec2-combined-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "ec2_combined_policy" {
  name        = "ec2-combined-policy"
  description = "Allows EC2 to use S3 and CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ],
        Resource = [
          "${aws_s3_bucket.ec2_s3_bucket.arn}",
          "${aws_s3_bucket.ec2_s3_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "cloudwatch:PutMetricData"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_combined_policy_attachment" {
  role       = aws_iam_role.ec2_combined_role.name
  policy_arn = aws_iam_policy.ec2_combined_policy.arn
}

resource "aws_iam_instance_profile" "ec2_combined_instance_profile" {
  name = "ec2-combined-instance-profile"
  role = aws_iam_role.ec2_combined_role.name
}


# S3 Bucket with UUID
resource "random_uuid" "test" {}

resource "aws_s3_bucket" "ec2_s3_bucket" {
  bucket        = "csye6225-s3-bucket-${random_uuid.test.result}"
  force_destroy = true
  tags = {
    Name = "csye6225-s3-bucket"
  }
}

# Enable S3 Versioning
resource "aws_s3_bucket_versioning" "s3_versioning" {
  bucket = aws_s3_bucket.ec2_s3_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-Side Encryption (AES256)
resource "aws_s3_bucket_server_side_encryption_configuration" "s3_encryption" {
  bucket = aws_s3_bucket.ec2_s3_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block Public Access (Ensures bucket privacy)
resource "aws_s3_bucket_public_access_block" "s3_public_access" {
  bucket = aws_s3_bucket.ec2_s3_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle Policy
resource "aws_s3_bucket_lifecycle_configuration" "s3_lifecycle" {
  bucket = aws_s3_bucket.ec2_s3_bucket.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

# RDS Subnet Group (Ensures RDS is in private subnets)
resource "aws_db_subnet_group" "rds_subnet_group" {
  name        = "rds-subnet-group"
  subnet_ids  = aws_subnet.private_subnets[*].id
  description = "Subnet Group for RDS"

  tags = {
    Name = "RDS Subnet Group"
  }
}


# RDS Parameter Group
resource "aws_db_parameter_group" "rds_param_group" {
  name   = "csye6225-mysql-params"
  family = "mysql8.0" # Adjust based on DB version

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "max_connections"
    value = "100"
  }

  tags = {
    Name = "CSYE6225 MySQL Parameter Group"
  }
}

# Update RDS instance to use the custom parameter group
resource "aws_db_instance" "rds_instance" {
  identifier             = "csye6225"
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0.32"
  instance_class         = "db.t3.micro"
  username               = var.DB_USER
  password               = var.DB_PASS
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  publicly_accessible    = false
  db_name                = var.DB_NAME
  skip_final_snapshot    = true
  parameter_group_name   = aws_db_parameter_group.rds_param_group.name # ✅ Attach custom parameter group

  tags = {
    Name = "CSYE6225 RDS Instance"
  }
}


# EC2 Instance (Using Packer AMI)
resource "aws_instance" "webapp" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.public_subnets[0].id
  vpc_security_group_ids      = [aws_security_group.webapp_sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_combined_instance_profile.name

  user_data = <<-EOF
#!/bin/bash
echo "Starting WebApp Setup"
exec > /var/log/user-data.log 2>&1
set -x

cd /home/csye6225/webapp

# Write environment variables
echo "DB_HOST=${aws_db_instance.rds_instance.address}" | sudo tee /home/csye6225/webapp/.env
echo "DB_USER=${var.DB_USER}" | sudo tee -a /home/csye6225/webapp/.env
echo "DB_PASS=${var.DB_PASS}" | sudo tee -a /home/csye6225/webapp/.env
echo "DB_NAME=${var.DB_NAME}" | sudo tee -a /home/csye6225/webapp/.env
echo "AWS_REGION=${var.AWS_REGION}" | sudo tee -a /home/csye6225/webapp/.env
echo "S3_BUCKET_NAME=${aws_s3_bucket.ec2_s3_bucket.id}" | sudo tee -a /home/csye6225/webapp/.env

sudo chmod 600 /home/csye6225/webapp/.env
sudo chown csye6225:csye6225 /home/csye6225/webapp/.env

# Restart application service
echo "Restarting Web Application Service"
sudo systemctl restart myapp || echo "Service restart failed"
sudo systemctl status myapp --no-pager || echo "Service is not running"

# CloudWatch Agent Configuration
echo "Creating CloudWatch Agent configuration..."
sudo mkdir -p /opt/aws/amazon-cloudwatch-agent/etc

sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json > /dev/null <<EOCONFIG
{
  "agent": {
    "metrics_collection_interval": 60,
    "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log",
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/home/csye6225/webapp/app.log",
            "log_group_name": "/csye6225/webapp/logs",
            "log_stream_name": "{instance_id}-app-log",
            "timestamp_format": "%Y-%m-%d %H:%M:%S"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "CSYE6225/WebApp",
    "metrics_collected": {
      "statsd": {
        "service_address": ":8125",
        "metrics_collection_interval": 10
      }
    }
  }
}
EOCONFIG

# Start CloudWatch Agent
echo "Starting CloudWatch Agent..."
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s

EOF


  tags = {
    Name = "WebApp EC2"
  }

  depends_on = [
    aws_security_group.webapp_sg,
    aws_internet_gateway.igw,
    aws_route_table_association.public_subnet_assoc,
    aws_db_instance.rds_instance
  ]
}


