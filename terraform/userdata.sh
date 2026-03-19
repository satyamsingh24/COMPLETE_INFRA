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

echo "=== Bootstrap Complete ==="

# ─────────────────────────────────────
# Jenkins Full Automation
# ─────────────────────────────────────

echo "=== Jenkins Automation Start ==="

# Jenkins ready hone ka wait
echo "Waiting for Jenkins..."
sleep 60
until curl -s http://localhost:8080/login > /dev/null 2>&1; do
  echo "Jenkins not ready yet..."
  sleep 10
done
echo "Jenkins is up!"

# Initial password
JENKINS_PASS=$(cat /var/lib/jenkins/secrets/initialAdminPassword)
echo "Jenkins initial password: $JENKINS_PASS"

# Jenkins CLI download
curl -fsSL http://localhost:8080/jnlpJars/jenkins-cli.jar \
  -o /tmp/jenkins-cli.jar || echo "CLI download failed"

# Groovy - Admin user + skip setup wizard
cat > /tmp/jenkins-setup.groovy << 'GROOVY'
import jenkins.model.*
import hudson.security.*
import jenkins.install.*

def instance = Jenkins.getInstance()

// Skip setup wizard
instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)

// Create admin user
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount("admin", "admin123")
instance.setSecurityRealm(hudsonRealm)

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

instance.save()
println "Admin user created successfully!"
GROOVY

# Run groovy script
java -jar /tmp/jenkins-cli.jar \
  -s http://localhost:8080 \
  -auth "admin:$JENKINS_PASS" \
  groovy = < /tmp/jenkins-setup.groovy || echo "Groovy setup failed"

sleep 10

# Install plugins
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
  -restart || echo "Plugin install failed"

echo "Waiting for Jenkins restart after plugins..."
sleep 90
until curl -s http://localhost:8080/login > /dev/null 2>&1; do
  echo "Waiting..."
  sleep 10
done
echo "Jenkins restarted!"

# Create Pipeline Job
cat > /tmp/pipeline-job.xml << 'JOBXML'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>COMPLETE_INFRA Pipeline</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>
      <triggers>
        <com.cloudbees.jenkins.GitHubPushTrigger plugin="github">
          <spec></spec>
        </com.cloudbees.jenkins.GitHubPushTrigger>
      </triggers>
    </org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.plugins.git.GitSCM" plugin="git">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>https://github.com/satyamsingh24/COMPLETE_INFRA.git</url>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/main</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
    </scm>
    <scriptPath>jenkins/Jenkinsfile</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
JOBXML

# Create job
java -jar /tmp/jenkins-cli.jar \
  -s http://localhost:8080 \
  -auth admin:admin123 \
  create-job COMPLETE_INFRA-Pipeline < /tmp/pipeline-job.xml || echo "Job creation failed"

sleep 5

# Trigger first build
java -jar /tmp/jenkins-cli.jar \
  -s http://localhost:8080 \
  -auth admin:admin123 \
  build COMPLETE_INFRA-Pipeline || echo "Build trigger failed"

PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "=== Jenkins Automation Complete ==="
echo "Jenkins URL  : http://$PUBLIC_IP:8080"
echo "Username     : admin"
echo "Password     : admin123"
echo "Job          : COMPLETE_INFRA-Pipeline"
echo "Build        : Triggered!"
