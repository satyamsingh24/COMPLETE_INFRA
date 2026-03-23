#!/bin/bash
set -x
exec > >(tee /var/log/userdata.log | logger -t user-data) 2>&1

echo "=== Bootstrap Start ==="

dnf update -y --allowerasing || echo "Update failed"
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

# Jenkins repo
tee /etc/yum.repos.d/jenkins.repo << 'JENREPO'
[jenkins]
name=Jenkins-Stable
baseurl=https://pkg.jenkins.io/redhat-stable/
gpgcheck=0
enabled=1
JENREPO

rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key || true
dnf install -y jenkins --nogpgcheck || { echo "Jenkins install failed"; exit 1; }

# Jenkins permissions
echo "jenkins ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/jenkins
chmod 440 /etc/sudoers.d/jenkins
usermod -aG docker jenkins

# App directory
mkdir -p /opt/app
chown -R jenkins:jenkins /opt/app
chmod -R 755 /opt/app

# JCasC config
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
    adminAddress: "admin@example.com"
CASC

chown -R jenkins:jenkins /var/lib/jenkins/casc_configs

# Jenkins URL config file - fixes CLI 403 error
mkdir -p /var/lib/jenkins
cat > /var/lib/jenkins/jenkins.model.JenkinsLocationConfiguration.xml << 'URLCONF'
<?xml version="1.1" encoding="UTF-8"?>
<jenkins.model.JenkinsLocationConfiguration>
  <adminAddress>admin@example.com</adminAddress>
  <jenkinsUrl>http://localhost:8080/</jenkinsUrl>
</jenkins.model.JenkinsLocationConfiguration>
URLCONF

chown jenkins:jenkins /var/lib/jenkins/jenkins.model.JenkinsLocationConfiguration.xml

# Jenkins systemd override
mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/override.conf << 'OVERRIDE'
[Service]
Environment="CASC_JENKINS_CONFIG=/var/lib/jenkins/casc_configs"
Environment="JAVA_OPTS=-Djenkins.install.runSetupWizard=false"
OVERRIDE

systemctl daemon-reload
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
  echo "Jenkins not ready..."
  sleep 10
done
echo "Jenkins is up!"

# Jenkins CLI
curl -fsSL http://localhost:8080/jnlpJars/jenkins-cli.jar -o /tmp/jenkins-cli.jar

# Install plugins
java -jar /tmp/jenkins-cli.jar \
  -s http://localhost:8080 \
  -auth admin:admin123 \
  install-plugin \
  git workflow-aggregator docker-workflow \
  amazon-ecr aws-credentials pipeline-aws \
  github job-dsl configuration-as-code pipeline-stage-view \
  -restart || echo "Plugin install failed"

echo "Waiting for restart..."
sleep 90
until curl -s http://localhost:8080/login > /dev/null 2>&1; do
  sleep 10
done
echo "Jenkins restarted!"

# Create Pipeline Job
cat > /tmp/pipeline-job.xml << 'JOBXML'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>COMPLETE_INFRA Pipeline</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
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
  <disabled>false</disabled>
</flow-definition>
JOBXML

java -jar /tmp/jenkins-cli.jar \
  -s http://localhost:8080 \
  -auth admin:admin123 \
  create-job COMPLETE_INFRA-Pipeline < /tmp/pipeline-job.xml || \
java -jar /tmp/jenkins-cli.jar \
  -s http://localhost:8080 \
  -auth admin:admin123 \
  update-job COMPLETE_INFRA-Pipeline < /tmp/pipeline-job.xml

echo "✅ Job created/updated!"

# Trigger build
java -jar /tmp/jenkins-cli.jar \
  -s http://localhost:8080 \
  -auth admin:admin123 \
  build COMPLETE_INFRA-Pipeline

echo "✅ Build triggered!"

PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "=== Bootstrap Complete ==="
echo "Jenkins : http://$PUBLIC_IP:8080"
echo "Username: admin"
echo "Password: admin123"

# ============ Container Monitor Setup ============
echo "=== Container Monitor Setup ==="

# Cronie install karo
dnf install -y cronie || true
systemctl enable crond
systemctl start crond

# Monitor script create karo
mkdir -p /opt/monitoring
cat > /opt/monitoring/container-monitor.sh << 'SCRIPT'
#!/bin/bash
SNS_TOPIC_ARN="arn:aws:sns:ap-south-1:176583374037:complete-infra-alerts"
AWS_REGION="ap-south-1"
CONTAINERS=("backend" "mysql" "redis" "nginx" "grafana" "prometheus")

for container in "${CONTAINERS[@]}"; do
  STATUS=$(docker inspect --format='{{.State.Status}}' $container 2>/dev/null)
  HEALTH=$(docker inspect --format='{{.State.Health.Status}}' $container 2>/dev/null)

  if [ "$STATUS" != "running" ]; then
    aws sns publish \
      --topic-arn $SNS_TOPIC_ARN \
      --subject "Container DOWN: $container" \
      --message "Container '$container' is DOWN!
Status: $STATUS
Time: $(date)
Instance: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)" \
      --region $AWS_REGION || true

  elif [ "$HEALTH" = "unhealthy" ]; then
    aws sns publish \
      --topic-arn $SNS_TOPIC_ARN \
      --subject "Container UNHEALTHY: $container" \
      --message "Container '$container' is UNHEALTHY!
Time: $(date)
Instance: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)" \
      --region $AWS_REGION || true
  fi
done
SCRIPT

chmod +x /opt/monitoring/container-monitor.sh
touch /var/log/container-monitor.log
chmod 666 /var/log/container-monitor.log

# Cron job setup
tee /etc/cron.d/container-monitor << 'CRON'
*/2 * * * * root /opt/monitoring/container-monitor.sh >> /var/log/container-monitor.log 2>&1
CRON

echo "=== Container Monitor Setup Complete ==="  #yees
