#!/bin/bash
set -x

# Logging (better)
exec > >(tee /var/log/userdata.log | logger -t user-data) 2>&1

echo "=== Bootstrap Start ==="

# ───────── System update ─────────
dnf update -y --allowerasing || echo "Update failed"

# ───────── Basic tools ─────────
dnf install -y git unzip curl java-17-amazon-corretto-headless --allowerasing || echo "Basic install failed"

# ───────── Docker ─────────
dnf install -y docker || { echo "Docker install failed"; exit 1; }
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

echo "Docker: $(docker --version)"

# ───────── Docker Compose ─────────
curl -fsSL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o /usr/local/bin/docker-compose || echo "Compose download failed"

chmod +x /usr/local/bin/docker-compose
echo "docker-compose: $(docker-compose --version)"

# ───────── Jenkins repo ─────────
tee /etc/yum.repos.d/jenkins.repo << 'JENREPO'
[jenkins]
name=Jenkins-Stable
baseurl=https://pkg.jenkins.io/redhat-stable/
gpgcheck=0
enabled=1
JENREPO

rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key || echo "Jenkins key import failed"

dnf install -y jenkins --nogpgcheck || { echo "Jenkins install failed"; exit 1; }

# ───────── Jenkins permissions ─────────
echo "jenkins ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/jenkins
chmod 440 /etc/sudoers.d/jenkins
usermod -aG docker jenkins

# ───────── App directory ─────────
mkdir -p /opt/app
chown -R jenkins:jenkins /opt/app
chmod -R 755 /opt/app

# ───────── Start Jenkins ─────────
systemctl enable jenkins
systemctl start jenkins

echo "Jenkins: $(systemctl is-active jenkins)"

# ───────── AWS CLI v2 (FIXED) ─────────
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -oq /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --update   # 🔥 important fix

echo "AWS CLI: $(aws --version)"

# ───────── Terraform ─────────
curl -fsSL -Lo /tmp/terraform.zip \
  https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip

unzip -oq /tmp/terraform.zip -d /tmp
mv -f /tmp/terraform /usr/local/bin/
chmod +x /usr/local/bin/terraform

echo "Terraform: $(terraform version | head -1)"

# ───────── Clone project (FIXED) ─────────
GITHUB_REPO="GITHUB_REPO_PLACEHOLDER"

rm -rf /opt/app/COMPLETE_INFRA   # 🔥 important
git clone "$GITHUB_REPO" /opt/app/COMPLETE_INFRA || echo "Clone failed"

chown -R jenkins:jenkins /opt/app/COMPLETE_INFRA

echo "=== Bootstrap Complete ==="

# ───────── Jenkins password ─────────
sleep 30
cat /var/lib/jenkins/secrets/initialAdminPassword || echo "Wait a bit..."