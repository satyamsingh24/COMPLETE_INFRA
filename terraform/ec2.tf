resource "aws_security_group" "jenkins_ec2" {
  name        = "${var.project_name}-jenkins-sg"
  description = "Allow SSH, Jenkins, HTTP"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }

  ingress {
    description = "Jenkins UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
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
    Name = "${var.project_name}-jenkins-sg"
  }
}

# IAM Role for EC2 (ECR + ECS access)
resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_full" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

resource "aws_iam_role_policy_attachment" "ecs_full" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}

resource "aws_iam_role_policy_attachment" "admin_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# Userdata Script
locals {
  userdata = <<-USERDATA
    #!/bin/bash
    set -e
    exec > /var/log/userdata.log 2>&1

    echo "==============================="
    echo " COMPLETE_INFRA Bootstrap Start"
    echo "==============================="

    # System update
    dnf update -y

    # Install Git
    dnf install -y git
    echo "✅ Git installed: $(git --version)"

    # Install Java 17 (headless - lightweight)
    dnf install -y java-17-amazon-corretto-headless
    echo "✅ Java installed: $(java -version 2>&1 | head -1)"

    # Install Docker
    dnf install -y docker
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user
    usermod -aG docker jenkins
    echo "✅ Docker installed: $(docker --version)"

    # Install Jenkins
    wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
    rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
    dnf install -y jenkins
    systemctl enable jenkins
    systemctl start jenkins
    echo "✅ Jenkins installed"

    # Install AWS CLI v2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    dnf install -y unzip
    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install
    echo "✅ AWS CLI installed: $(aws --version)"

    # Install Terraform
    dnf install -y yum-utils
    yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
    dnf install -y terraform
    echo "✅ Terraform installed: $(terraform version | head -1)"

    # Clone Project
    cd /home/ec2-user
    git clone ${var.github_repo_url} COMPLETE_INFRA || echo "⚠️  Clone failed - repo may be private or URL wrong"
    chown -R ec2-user:ec2-user /home/ec2-user/COMPLETE_INFRA || true

    echo "==============================="
    echo " Bootstrap Complete!"
    echo "==============================="
    echo "Jenkins Password: $(cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || echo 'not ready yet')"
  USERDATA
}

# EC2 Instance
resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.jenkins_ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  key_name               = var.key_name

  user_data = local.userdata

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name        = "${var.project_name}-jenkins-server"
    Environment = var.environment
  }
}