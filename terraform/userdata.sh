#!/bin/bash
set -x
exec > >(tee /var/log/userdata.log | logger -t user-data) 2>&1

echo "=== Bootstrap Start ==="

# System update
dnf update -y --allowerasing || echo "Update failed"

# Basic tools
dnf install -y git unzip curl java-17-amazon-corretto-headless --allowerasing || echo "Basic install failed"

# Docker
dnf install -y docker || { echo "Docker install failed"; exit 1; }
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user
echo "Docker: $(docker --version)"

# Docker Compose
curl -fsSL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o /usr/local/bin/docker-compose || echo "Compose download failed"
chmod +x /usr/local/bin/docker-compose
echo "docker-compose: $(docker-compose --version)"

# Jenkins repo
tee /etc/yum.repos.d/jenkins.repo << 'JENREPO'
[jenkins]
name=Jenkins-Stable
baseurl=https://pkg.jenkins.io/redhat-stable/
gpgcheck=0
enabled=1
JENREPO

rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key || echo "Jenkins key import failed"
dnf install -y jenkins --nogpgcheck || { echo "Jenkins install failed"; exit 1; }

# Jenkins permissions
echo "jenkins ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/jenkins
chmod 440 /etc/sudoers.d/jenkins
usermod -aG docker jenkins

# App directory
mkdir -p /opt/app
chown -R jenkins:jenkins /opt/app
chmod -R 755 /opt/app

# JCasC config - Admin user + skip wizard
mkdir -p /var/lib/jenkins/casc_configs
cat > /var/lib/jenkins/casc_configs/jenkins.yaml << 'CASC'
jenkins:
  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: "admin"
          password: "admin123"
  authorizationStrategy:
    loggedInUsersCanDoAnything:
      allowAnonymousRead: false
  numExecutors: 2
  slaveAgentPort: 50000
unclassified:
  location:
    url: "http://localhost:8080/"
jobs:
  - script: >
      pipelineJob('COMPLETE_INFRA-Pipeline') {
        definition {
          cpsScm {
            scm {
              git {
                remote {
                  url('https://github.com/satyamsingh24/COMPLETE_INFRA.git')
                }
                branch('*/main')
              }
            }
            scriptPath('jenkins/Jenkinsfile')
          }
        }
        triggers {
          githubPush()
        }
      }
CASC

chown -R jenkins:jenkins /var/lib/jenkins/casc_configs

# Jenkins systemd override - skip wizard + JCasC
mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/override.conf << 'OVERRIDE'
[Service]
Environment="CASC_JENKINS_CONFIG=/var/lib/jenkins/casc_configs"
Environment="JAVA_OPTS=-Djenkins.install.runSetupWizard=false"
OVERRIDE

systemctl daemon-reload

# Start Jenkins
systemctl enable jenkins
systemctl start jenkins
echo "Jenkins: $(systemctl is-active jenkins)"

# AWS CLI v2
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -oq /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --update
echo "AWS CLI: $(aws --version)"

# Terraform
curl -fsSL -Lo /tmp/terraform.zip \
  https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip
unzip -oq /tmp/terraform.zip -d /tmp
mv -f /tmp/terraform /usr/local/bin/
chmod +x /usr/local/bin/terraform
echo "Terraform: $(terraform version | head -1)"

# Clone project
GITHUB_REPO="GITHUB_REPO_PLACEHOLDER"
rm -rf /opt/app/COMPLETE_INFRA
git clone "$GITHUB_REPO" /opt/app/COMPLETE_INFRA || echo "Clone failed"
chown -R jenkins:jenkins /opt/app/COMPLETE_INFRA

# Wait for Jenkins
echo "Waiting for Jenkins..."
sleep 90
until curl -s http://localhost:8080/login > /dev/null 2>&1; do
  echo "Jenkins not ready yet..."
  sleep 10
done
echo "Jenkins is up!"

# Install plugins via CLI
curl -fsSL http://localhost:8080/jnlpJars/jenkins-cli.jar -o /tmp/jenkins-cli.jar

java -jar /tmp/jenkins-cli.jar \
  -s http://localhost:8080 \
  -auth admin:admin123 \
  install-plugin \
  git \
  workflow-aggregator \
  docker-workflow \
  amazon-ecr \
  aws-credentials \
  pipeline-aws \
  github \
  job-dsl \
  configuration-as-code \
  -restart || echo "Plugin install failed"

echo "Waiting for restart..."
sleep 90
until curl -s http://localhost:8080/login > /dev/null 2>&1; do
  sleep 10
done

# Trigger build
java -jar /tmp/jenkins-cli.jar \
  -s http://localhost:8080 \
  -auth admin:admin123 \
  build COMPLETE_INFRA-Pipeline || echo "Build trigger failed"

PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "=== Bootstrap Complete ==="
echo "Jenkins URL : http://$PUBLIC_IP:8080"
echo "Username    : admin"
echo "Password    : admin123"
