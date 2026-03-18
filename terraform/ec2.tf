# Security Group
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

  ingress {
    description = "App Port"
    from_port   = 5000
    to_port     = 5000
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

# IAM Role for EC2
resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = [
          "ec2.amazonaws.com",
          "ecs.amazonaws.com",
          "ecs-tasks.amazonaws.com"
        ]
      }
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

# Userdata Script - Fixed Version
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

    # Install basic tools (curl, unzip, git)
    dnf install -y git curl unzip

    echo "✅ Git: $(git --version)"

    # Install Java 17 headless
    dnf install -y java-17-amazon-corretto-headless
    echo "✅ Java: $(java -version 2>&1 | head -1)"

    # Install Docker
    dnf install -y docker
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user
    echo "✅ Docker: $(docker --version)"

    # Install Jenkins via curl
    curl -o /etc/yum.repos.d/jenkins.repo \
      https://pkg.jenkins.io/redhat-stable/jenkins.repo
    rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
    dnf install -y jenkins --nogpgcheck
    
    # Add jenkins to docker group
    usermod -aG docker jenkins

    # Fix Jenkins config before first start
    # Set slaveAgentPort to 50000 (not -1)
    mkdir -p /var/lib/jenkins
    cat > /var/lib/jenkins/config.xml << 'JENKINSCONF'
<?xml version='1.1' encoding='UTF-8'?>
<hudson>
  <disabledAdministrativeMonitors>
    <string>jenkins.diagnostics.ControllerExecutorsNoAgents</string>
    <string>hudson.node_monitors.MonitorMarkedNodeOffline</string>
  </disabledAdministrativeMonitors>
  <version>2.541.2</version>
  <numExecutors>2</numExecutors>
  <mode>NORMAL</mode>
  <useSecurity>true</useSecurity>
  <authorizationStrategy class="hudson.security.FullControlOnceLoggedInAuthorizationStrategy">
    <denyAnonymousReadAccess>true</denyAnonymousReadAccess>
  </authorizationStrategy>
  <securityRealm class="hudson.security.HudsonPrivateSecurityRealm">
    <disableSignup>true</disableSignup>
    <enableCaptcha>false</enableCaptcha>
  </securityRealm>
  <disableRememberMe>false</disableRememberMe>
  <projectNamingStrategy class="jenkins.model.ProjectNamingStrategy$DefaultProjectNamingStrategy"/>
  <workspaceDir>/var/lib/jenkins/workspace/$${ITEM_FULL_NAME}</workspaceDir>
  <buildsDir>/var/lib/jenkins/builds/$${ITEM_ROOTDIR}</buildsDir>
  <jdks/>
  <viewsTabBar class="hudson.views.DefaultViewsTabBar"/>
  <myViewsTabBar class="hudson.views.DefaultMyViewsTabBar"/>
  <clouds/>
  <scmCheckoutRetryCount>0</scmCheckoutRetryCount>
  <views>
    <hudson.model.AllView>
      <owner class="hudson" reference="../../.."/>
      <name>all</name>
      <filterExecutors>false</filterExecutors>
      <filterQueue>false</filterQueue>
      <properties class="hudson.model.View$PropertyList"/>
    </hudson.model.AllView>
  </views>
  <primaryView>all</primaryView>
  <slaveAgentPort>50000</slaveAgentPort>
  <label></label>
  <crumbIssuer class="hudson.security.csrf.DefaultCrumbIssuer">
    <excludeClientIPFromCrumb>false</excludeClientIPFromCrumb>
  </crumbIssuer>
  <nodeProperties/>
  <globalNodeProperties/>
</hudson>
JENKINSCONF

    chown -R jenkins:jenkins /var/lib/jenkins
    systemctl enable jenkins
    systemctl start jenkins
    echo "✅ Jenkins started"

    # Install AWS CLI v2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
      -o "/tmp/awscliv2.zip"
    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install
    echo "✅ AWS CLI: $(aws --version)"

    # Install Terraform via binary (repo method fails on AL2023)
    curl -Lo /tmp/terraform.zip \
      https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip
    unzip -q /tmp/terraform.zip -d /tmp
    mv /tmp/terraform /usr/local/bin/
    chmod +x /usr/local/bin/terraform
    echo "✅ Terraform: $(terraform version | head -1)"

    # Clone Project
    cd /home/ec2-user
    git clone ${var.github_repo_url} COMPLETE_INFRA \
      || echo "⚠️ Clone failed - check repo URL"
    chown -R ec2-user:ec2-user /home/ec2-user/COMPLETE_INFRA || true

    # Expand /tmp (fix for Jenkins offline issue)
    mount -o remount,size=2G /tmp || true

    echo "==============================="
    echo " Bootstrap Complete!"
    echo "==============================="
    echo "Jenkins Password: $(cat /var/lib/jenkins/secrets/initialAdminPassword \
      2>/dev/null || echo 'not ready yet - check again in 2 min')"
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

resource "aws_security_group_rule" "ecs_from_alb" {
  type                     = "ingress"
  from_port                = 5000
  to_port                  = 5000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.jenkins_ec2.id
  description              = "Allow ALB to ECS on port 5000"
}
