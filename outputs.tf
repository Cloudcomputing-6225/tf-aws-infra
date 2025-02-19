
output "vpc_ids" {
  description = "List of created VPC IDs"
  value       = aws_vpc.vpc[*].id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public_subnets[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private_subnets[*].id
}

output "internet_gateway_ids" {
  description = "List of Internet Gateway IDs"
  value       = aws_internet_gateway.igw[*].id
}
