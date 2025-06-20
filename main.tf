# Fetch available AWS zones
data "aws_availability_zones" "available" {}

data "aws_caller_identity" "current" {}


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
resource "aws_security_group" "alb_sg" {
  name        = "alb-security-group"
  description = "Allow HTTP and HTTPS from anywhere"
  vpc_id      = aws_vpc.vpc.id

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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ALB Security Group"
  }
}

# Updated Security Group for WebApp EC2
resource "aws_security_group" "webapp_sg" {
  vpc_id = aws_vpc.vpc.id
  name   = "webapp-security-group"

  ingress {
    description = "Allow SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "Allow app traffic from ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
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

# Application Load Balancer
resource "aws_lb" "app_alb" {
  name               = "csye6225-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public_subnets[*].id

  tags = {
    Name = "CSYE6225 ALB"
  }
}

# Target Group
resource "aws_lb_target_group" "app_tg" {
  name     = "csye6225-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id

  health_check {
    path                = "/healthz"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name = "CSYE6225 TG"
  }
}


resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.ssl_cert_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
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

resource "aws_kms_key" "ec2_key" {
  description             = "KMS key for EC2 encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid : "Enable IAM User Permissions",
        Effect : "Allow",
        Principal : {
          AWS : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action : "kms:*",
        Resource : "*"
      },
      {
        Sid : "Allow access for Key Administrators",
        Effect : "Allow",
        Principal : {
          AWS : "*"
        },
        Action : [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion"
        ],
        Resource : "*"
      },
      {
        Sid : "Allow use of the key",
        Effect : "Allow",
        Principal : {
          AWS : "*"
        },
        Action : [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource : "*"
      },
      {
        Sid : "Allow attachment of persistent resources",
        Effect : "Allow",
        Principal : {
          AWS : "*"
        },
        Action : [
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ],
        Resource : "*",
        Condition : {
          Bool : {
            "kms:GrantIsForAWSResource" : "true"
          }
        }
      }
    ]
  })

}

resource "aws_kms_alias" "ec2_alias" {
  name          = "alias/custom/ec2"
  target_key_id = aws_kms_key.ec2_key.key_id
}

resource "aws_kms_key" "rds_key" {
  description             = "KMS key for RDS encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid : "Enable IAM User Permissions",
        Effect : "Allow",
        Principal : {
          AWS : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action : "kms:*",
        Resource : "*"
      },
      {
        Sid : "Allow access for Key Administrators",
        Effect : "Allow",
        Principal : {
          AWS : "*"
        },
        Action : [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion"
        ],
        Resource : "*"
      },
      {
        Sid : "Allow use of the key",
        Effect : "Allow",
        Principal : {
          AWS : "*"
        },
        Action : [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource : "*"
      },
      {
        Sid : "Allow attachment of persistent resources",
        Effect : "Allow",
        Principal : {
          AWS : "*"
        },
        Action : [
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ],
        Resource : "*",
        Condition : {
          Bool : {
            "kms:GrantIsForAWSResource" : "true"
          }
        }
      }
    ]
  })

}

resource "aws_kms_alias" "rds_alias" {
  name          = "alias/custom/rds"
  target_key_id = aws_kms_key.rds_key.key_id
}

resource "aws_kms_key" "s3_key" {
  description             = "KMS key for S3 encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid : "Enable IAM User Permissions",
        Effect : "Allow",
        Principal : {
          AWS : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action : "kms:*",
        Resource : "*"
      },
      {
        Sid : "Allow access for Key Administrators",
        Effect : "Allow",
        Principal : {
          AWS : "*"
        },
        Action : [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion"
        ],
        Resource : "*"
      },
      {
        Sid : "Allow use of the key",
        Effect : "Allow",
        Principal : {
          AWS : "*"
        },
        Action : [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource : "*"
      },
      {
        Sid : "Allow attachment of persistent resources",
        Effect : "Allow",
        Principal : {
          AWS : "*"
        },
        Action : [
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ],
        Resource : "*",
        Condition : {
          Bool : {
            "kms:GrantIsForAWSResource" : "true"
          }
        }
      }
    ]
  })

}

resource "aws_kms_alias" "s3_alias" {
  name          = "alias/custom/s3"
  target_key_id = aws_kms_key.s3_key.key_id
}

resource "aws_kms_key" "secrets_key" {
  description             = "KMS key for Secrets Manager"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid : "Enable IAM User Permissions",
        Effect : "Allow",
        Principal : {
          AWS : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action : "kms:*",
        Resource : "*"
      },
      {
        Sid : "Allow access for Key Administrators",
        Effect : "Allow",
        Principal : {
          AWS : "*"
        },
        Action : [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion"
        ],
        Resource : "*"
      },
      {
        Sid : "Allow use of the key",
        Effect : "Allow",
        Principal : {
          AWS : "*"
        },
        Action : [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource : "*"
      },
      {
        Sid : "Allow attachment of persistent resources",
        Effect : "Allow",
        Principal : {
          AWS : "*"
        },
        Action : [
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ],
        Resource : "*",
        Condition : {
          Bool : {
            "kms:GrantIsForAWSResource" : "true"
          }
        }
      }
    ]
  })

}

resource "aws_kms_alias" "secrets_alias" {
  name          = "alias/custom/secrets"
  target_key_id = aws_kms_key.secrets_key.key_id
}

# Create Secrets Manager secret and store DB credentials
resource "random_password" "rds_password" {
  length           = 16
  upper            = true
  lower            = true
  numeric          = true
  special          = true
  override_special = "!#$%^&*()-_=+[]{}:;<>?.," # ✅ safe specials
}

resource "aws_secretsmanager_secret" "rds_secret" {
  name_prefix = "rds-db-secret-"
  description = "RDS DB credentials"
  kms_key_id  = aws_kms_key.secrets_key.arn
}

resource "aws_secretsmanager_secret_version" "rds_secret_version" {
  secret_id = aws_secretsmanager_secret.rds_secret.id
  secret_string = jsonencode({
    username = var.DB_USER,
    password = random_password.rds_password.result,
    db_name  = var.DB_NAME,
    host     = aws_db_instance.rds_instance.address,
    port     = 3306
  })
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
      },
      {
        "Effect" : "Allow",
        "Action" : "secretsmanager:GetSecretValue",
        "Resource" : "*"
      },
      {
        Effect = "Allow",
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ],
        Resource = [
          aws_kms_key.ec2_key.arn,
          aws_kms_key.rds_key.arn,
          aws_kms_key.s3_key.arn,
          aws_kms_key.secrets_key.arn
        ]
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
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3_key.arn
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
  password               = random_password.rds_password.result
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  publicly_accessible    = false
  db_name                = var.DB_NAME
  skip_final_snapshot    = true
  parameter_group_name   = aws_db_parameter_group.rds_param_group.name # ✅ Attach custom parameter group
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.rds_key.arn

  tags = {
    Name = "CSYE6225 RDS Instance"
  }
}

# Launch Template
resource "aws_launch_template" "webapp_lt" {
  name          = "csye6225-webapp"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_combined_instance_profile.name
  }

  network_interfaces {
    security_groups             = [aws_security_group.webapp_sg.id]
    associate_public_ip_address = true
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 20
      volume_type           = "gp2"
      encrypted             = true
      kms_key_id            = aws_kms_key.ec2_key.arn
      delete_on_termination = true
    }
  }


  user_data = base64encode(<<-EOF
  #!/bin/bash
  echo "Starting WebApp Setup"
  exec > /var/log/user-data.log 2>&1
  set -x

  cd /home/csye6225/webapp

  # Install AWS CLI if not already installed
  apt-get update
  apt-get install -y awscli jq

  for i in {1..10}; do
    SECRET=$(aws secretsmanager get-secret-value \
      --secret-id=${aws_secretsmanager_secret.rds_secret.id}\
      --region us-east-1 \
      --query SecretString \
      --output text)

    if [ -n "$SECRET" ]; then
      echo "Fetched secret!" >> /var/log/user-data.log
      break
    fi

    echo "Waiting for secret..." >> /var/log/user-data.log
    sleep 10
  done

  DB_USER=$(echo $SECRET | jq -r '.username')
  DB_PASS=$(echo $SECRET | jq -r '.password')
  DB_NAME=$(echo $SECRET | jq -r '.db_name')
  DB_HOST=$(echo $SECRET | jq -r '.host')

  echo "DB_HOST=$DB_HOST" | sudo tee /home/csye6225/webapp/.env
  echo "DB_USER=$DB_USER" | sudo tee -a /home/csye6225/webapp/.env
  echo "DB_PASS=$DB_PASS" | sudo tee -a /home/csye6225/webapp/.env
  echo "DB_NAME=$DB_NAME" | sudo tee -a /home/csye6225/webapp/.env
  echo "AWS_REGION=us-east-1" | sudo tee -a /home/csye6225/webapp/.env
  echo "S3_BUCKET_NAME=${aws_s3_bucket.ec2_s3_bucket.id}" | sudo tee -a /home/csye6225/webapp/.env
  echo "PORT=3000" | sudo tee -a /home/csye6225/webapp/.env



  sudo chown csye6225:csye6225 /home/csye6225/webapp/.env
  sudo chmod 600 /home/csye6225/webapp/.env


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

  sudo chmod 644 /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

  sudo chmod 644 /home/csye6225/webapp/app.log  

  sudo systemctl daemon-reload
  sudo systemctl restart myapp
  sudo systemctl restart amazon-cloudwatch-agent

  EOF
  )
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "csye6225-webapp-instance"
    }
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "webapp_asg" {
  name                = "csye6225-asg"
  max_size            = 5
  min_size            = 3
  desired_capacity    = 3
  vpc_zone_identifier = aws_subnet.public_subnets[*].id
  launch_template {
    id      = aws_launch_template.webapp_lt.id
    version = "$Latest"
  }

  target_group_arns         = [aws_lb_target_group.app_tg.arn]
  health_check_type         = "EC2"
  health_check_grace_period = 60
  default_cooldown          = 60

  tag {
    key                 = "Name"
    value               = "csye6225-webapp-instance"
    propagate_at_launch = true
  }
}

# CloudWatch Scale-Up Policy
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 60
  autoscaling_group_name = aws_autoscaling_group.webapp_asg.name
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 5
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.webapp_asg.name
  }
}

# CloudWatch Scale-Down Policy
resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 60
  autoscaling_group_name = aws_autoscaling_group.webapp_asg.name
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 3
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.webapp_asg.name
  }
}

# Route 53 DNS Record for Load Balancer
resource "aws_route53_record" "webapp_dns" {
  zone_id = var.route53_zone_id
  name    = var.subdomain_name
  type    = "A"

  alias {
    name                   = aws_lb.app_alb.dns_name
    zone_id                = aws_lb.app_alb.zone_id
    evaluate_target_health = true
  }
}
