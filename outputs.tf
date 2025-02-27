output "instance_id" {
  description = "ID of the created EC2 instance"
  value       = aws_instance.webapp.id
}

output "instance_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.webapp.public_ip
}

output "internet_gateway_ids" {
  description = "List of Internet Gateway IDs"
  value       = aws_internet_gateway.igw[*].id
}

output "private_subnet_ids" {
  description = "List of Private Subnet IDs"
  value       = aws_subnet.private_subnets[*].id
}

output "public_subnet_ids" {
  description = "List of Public Subnet IDs"
  value       = aws_subnet.public_subnets[*].id
}

output "security_group_ids" {
  description = "List of Security Group IDs"
  value       = aws_security_group.webapp_sg[*].id
}

output "vpc_ids" {
  description = "List of VPC IDs"
  value       = aws_vpc.vpc[*].id
}
