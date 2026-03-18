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
  description = "SSH command to connect"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${aws_instance.jenkins.public_ip}"
}