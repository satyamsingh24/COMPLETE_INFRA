variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "complete-infra"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "EC2 Key Pair name"
  type        = string
  default     = "complete-infra-key"
}

variable "your_ip" {
  description = "Your public IP for SSH access"
  type        = string
  default     = "0.0.0.0/0"
}

variable "github_repo_url" {
  description = "GitHub repo URL to clone"
  type        = string
  default     = "https://github.com/satyamsingh24/COMPLETE_INFRA.git"
}