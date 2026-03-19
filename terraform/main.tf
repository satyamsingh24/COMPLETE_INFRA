terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Fetch latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Terraform apply hone ke baad GitHub pe push karo
resource "null_resource" "git_push" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-CMD
      cd ${path.module}/..
      git add .
      git commit -m "Auto push after terraform apply - $(date)" || true
      git push origin main || true
    CMD
  }

  depends_on = [aws_instance.jenkins]
}
