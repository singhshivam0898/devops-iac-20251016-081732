```terraform
# Configure the AWS provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}

# --- Variables ---

variable "aws_region" {
  description = "The AWS region to deploy resources into."
  type        = string
  default     = "us-east-1" # N. Virginia
}

variable "project_name" {
  description = "Name of the project for resource tagging."
  type        = string
  default     = "MyWebApp"
}

variable "environment" {
  description = "Deployment environment (e.g., dev, staging, prod)."
  type        = string
  default     = "production"
}

variable "instance_type" {
  description = "The type of EC2 instance to launch."
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "The AMI ID for the EC2 instance. Find latest Amazon Linux 2 AMI for your region."
  type        = string
  # Example for us-east-1, always find the latest for your region
  default     = "ami-053b04d416b25102d"
}

variable "desired_capacity" {
  description = "The desired number of EC2 instances in the Auto Scaling Group."
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "The maximum number of EC2 instances in the Auto Scaling Group."
  type        = number
  default     = 3
}

variable "min_capacity" {
  description = "The minimum number of EC2 instances in the Auto Scaling Group."
  type        = number
  default     = 1
}

variable "health_check_grace_period" {
  description = "The amount of time, in seconds, that Auto Scaling waits before checking the health status of an EC2 instance."
  type        = number
  default     = 300
}

variable "health_check_type" {
  description = "The service to use for the health checks. Valid values are EC2 and ELB."
  type        = string
  default     = "ELB"
}

variable "vpc_cidr_block" {
  description = "The CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "A list of CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "A list of CIDR blocks for private subnets."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "key_pair_name" {
  description = "The name of the EC2 Key Pair to allow SSH access."
  type        = string
  default     = "my-ec2-keypair" # Ensure this key pair exists in your AWS account
}

# --- Networking (VPC, Subnets, Internet Gateway, Route Tables) ---

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-vpc"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-${var.environment}-igw"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-public-rt"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  # Private subnets typically route traffic through a NAT Gateway for outbound internet access
  # For simplicity, this example doesn't include a NAT Gateway, but it's crucial for production.
  # If you add a NAT Gateway, uncomment and configure the route below:
  # route {
  #   cidr_block = "0.0.0.0/0"
  #   nat_gateway_id = aws_nat_gateway.main.id
  # }

  tags = {
    Name        = "${var.project_name}-${var.environment}-private-rt"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true # Public subnets should auto-assign public IPs

  tags = {
    Name        = "${var.project_name}-${var.environment}-public-subnet-${count.index + 1}"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "${var.project_name}-${var.environment}-private-subnet-${count.index + 1}"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

data "aws_availability_zones" "available" {
  state = "available"
}

# --- Security Groups ---

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "Allow HTTP/HTTPS traffic to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow HTTP from anywhere
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow HTTPS from anywhere
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # Allow all outbound traffic
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-alb-sg"
