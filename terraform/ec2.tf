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

  ingress {
    description = "Backend Port"
    from_port   = 8085
    to_port     = 8086
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

locals {
  userdata = <<-USERDATA
    #!/bin/bash
    exec > /tmp/userdata.log 2>&1
    echo "=== Bootstrap Start ==="

    # System update
    dnf update -y --allowerasing || true

    # Basic tools - allowerasing fixes curl-minimal conflict
    dnf install -y git unzip --allowerasing || true
    dnf install -y java-17-amazon-corretto-headless --allowerasing || true

    # Docker
    dnf install -y docker || true
    systemctl enable docker || true
    systemctl start docker || true
    usermod -aG docker ec2-user || true
    echo "Docker: $(docker --version 2>/dev/null)" >> /tmp/userdata.log

    # docker-compose
    curl -fsSL https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64 \
      -o /usr/local/bin/docker-compose || true
    chmod +x /usr/local/bin/docker-compose || true
    echo "docker-compose: $(docker-compose --version 2>/dev/null)" >> /tmp/userdata.log

    # Jenkins repo - tee method (curl redirect fix)
    tee /etc/yum.repos.d/jenkins.repo << 'JENREPO'
[jenkins]
name=Jenkins-Stable
baseurl=https://pkg.jenkins.io/redhat-stable/
gpgcheck=0
enabled=1
JENREPO
    rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key || true
    dnf install -y jenkins --nogpgcheck || true
    echo "Jenkins installed: $?" >> /tmp/userdata.log

    # Jenkins sudoers - NO PASSWORD
    echo "jenkins ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/jenkins
    chmod 440 /etc/sudoers.d/jenkins

    # Jenkins docker group
    usermod -aG docker jenkins || true

    # /opt/app directory for deployments
    mkdir -p /opt/app
    chown -R jenkins:jenkins /opt/app
    chmod -R 755 /opt/app

    # Jenkins config - fix node offline + slaveAgentPort
    mkdir -p /var/lib/jenkins
    cat > /var/lib/jenkins/config.xml << 'JENKINSCONF'
<?xml version='1.1' encoding='UTF-8'?>
<hudson>
  <disabledAdministrativeMonitors>
    <string>jenkins.diagnostics.ControllerExecutorsNoAgents</string>
    <string>hudson.node_monitors.MonitorMarkedNodeOffline</string>
  </disabledAdministrativeMonitors>
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

    chown -R jenkins:jenkins /var/lib/jenkins || true
    systemctl enable jenkins || true
    systemctl start jenkins || true
    echo "Jenkins status: $(systemctl is-active jenkins)" >> /tmp/userdata.log

    # AWS CLI v2
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
      -o "/tmp/awscliv2.zip" || true
    unzip -q /tmp/awscliv2.zip -d /tmp || true
    /tmp/aws/install || true
    echo "AWS CLI: $(aws --version 2>/dev/null)" >> /tmp/userdata.log

    # Terraform binary
    curl -fsSL -Lo /tmp/terraform.zip \
      https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip || true
    unzip -q /tmp/terraform.zip -d /tmp || true
    mv /tmp/terraform /usr/local/bin/ || true
    chmod +x /usr/local/bin/terraform || true
    echo "Terraform: $(terraform version 2>/dev/null | head -1)" >> /tmp/userdata.log

    # Clone project
    git clone ${var.github_repo_url} /opt/app/COMPLETE_INFRA || true
    chown -R jenkins:jenkins /opt/app/COMPLETE_INFRA || true

    echo "=== Bootstrap Complete ===" >> /tmp/userdata.log
    echo "Jenkins Password: $(cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || echo 'wait 2 min')" >> /tmp/userdata.log
  USERDATA
}

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
