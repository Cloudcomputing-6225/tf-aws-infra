output "instance_id" {
  description = "ID of the created EC2 instance"
  value       = aws_instance.webapp.id
}

output "instance_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.webapp.public_ip
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.rds_instance.endpoint
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.ec2_s3_bucket.id
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.vpc.id
}

output "public_subnet_ids" {
  description = "List of Public Subnet IDs"
  value       = aws_subnet.public_subnets[*].id
}

output "private_subnet_ids" {
  description = "List of Private Subnet IDs"
  value       = aws_subnet.private_subnets[*].id
}

output "security_group_webapp" {
  description = "Security Group ID for WebApp"
  value       = aws_security_group.webapp_sg.id
}

output "security_group_rds" {
  description = "Security Group ID for RDS"
  value       = aws_security_group.rds_sg.id
}
