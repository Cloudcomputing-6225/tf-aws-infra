
data "aws_availability_zones" "available" {}

resource "aws_vpc" "vpc" {
  count = varr.vpc_count

  cidr_block           = var.vpc_cidr_blocks[count.index]
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "VPC-${count.index + 1}-${var.project_name}"
  }
}

resource "aws_subnet" "public_subnets" {
  count                   = var.vpc_count * 3 # 3 subnets per VPC
  vpc_id                  = aws_vpc.vpc[floor(count.index / 3)].id
  cidr_block              = cidrsubnet(var.vpc_cidr_blocks[floor(count.index / 3)], 8, count.index % 3)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index % 3)
  map_public_ip_on_launch = true

  tags = {
    Name = "Public-Subnet-${count.index + 1}-VPC-${floor(count.index / 3) + 1}"
  }
}

# Create Private Subnets
resource "aws_subnet" "private_subnets" {
  count             = var.vpc_count * 3 # 3 subnets per VPC
  vpc_id            = aws_vpc.vpc[floor(count.index / 3)].id
  cidr_block        = cidrsubnet(var.vpc_cidr_blocks[floor(count.index / 3)], 8, count.index % 3 + 3)
  availability_zone = element(data.aws_availability_zones.available.names, count.index % 3)

  tags = {
    Name = "Private-Subnet-${count.index + 1}-VPC-${floor(count.index / 3) + 1}"
  }
}

# Internet Gateway for Each VPC
resource "aws_internet_gateway" "igw" {
  count  = var.vpc_count
  vpc_id = aws_vpc.vpc[count.index].id

  tags = {
    Name = "IGW-VPC-${count.index + 1}"
  }
}

# Public Route Table
resource "aws_route_table" "public_routes" {
  count  = var.vpc_count
  vpc_id = aws_vpc.vpc[count.index].id

  tags = {
    Name = "Public-Route-Table-VPC-${count.index + 1}"
  }
}

resource "aws_route" "public_internet_access" {
  count = var.vpc_count

  route_table_id         = aws_route_table.public_routes[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw[count.index].id
}
resource "aws_route_table_association" "public_associations" {
  count          = var.vpc_count * 3
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_routes[floor(count.index / 3)].id
}

# Private Route Table
resource "aws_route_table" "private_routes" {
  count  = var.vpc_count
  vpc_id = aws_vpc.vpc[count.index].id

  tags = {
    Name = "Private-Route-Table-VPC-${count.index + 1}"
  }
}

# Associate Private Subnets with Private Route Table
resource "aws_route_table_association" "private_associations" {
  count          = var.vpc_count * 3
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_routes[floor(count.index / 3)].id
}
