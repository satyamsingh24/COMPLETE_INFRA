output "ec2_public_ip" {
  description = "EC2 Public IP"
  value       = aws_instance.jenkins.public_ip
}

output "ec2_public_dns" {
  description = "EC2 Public DNS"
  value       = aws_instance.jenkins.public_dns
}

output "jenkins_url" {
  description = "Jenkins URL"
  value       = "http://${aws_instance.jenkins.public_ip}:8080"
}

output "ssh_command" {
  description = "SSH command"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${aws_instance.jenkins.public_ip}"
}

output "alb_dns" {
  description = "ALB DNS - App URL"
  value       = "http://${aws_lb.app.dns_name}"
}

output "ecr_repository_uri" {
  description = "ECR Repository URI"
  value       = aws_ecr_repository.app.repository_url
}

output "sns_topic_arn" {
  description = "SNS Topic ARN"
  value       = aws_sns_topic.alerts.arn
}
