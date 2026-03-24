# ─────────────────────────────────────────────
# Grafana IAM User (CloudWatch Read Access)
# ─────────────────────────────────────────────
resource "aws_iam_user" "grafana_user" {
  name = "${var.project_name}-grafana-user"
  tags = {
    Name = "${var.project_name}-grafana-user"
  }
}

# ─────────────────────────────────────────────
# Attach CloudWatch Read Permissions
# ─────────────────────────────────────────────
resource "aws_iam_user_policy_attachment" "grafana_cw" {
  user       = aws_iam_user.grafana_user.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

resource "aws_iam_user_policy_attachment" "grafana_logs" {
  user       = aws_iam_user.grafana_user.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsReadOnlyAccess"
}

# ─────────────────────────────────────────────
# Create Access Key
# ─────────────────────────────────────────────
resource "aws_iam_access_key" "grafana_key" {
  user = aws_iam_user.grafana_user.name
}

# ─────────────────────────────────────────────
# Outputs (IMPORTANT)
# ─────────────────────────────────────────────
output "grafana_access_key" {
  value = aws_iam_access_key.grafana_key.id
}

output "grafana_secret_key" {
  value     = aws_iam_access_key.grafana_key.secret
  sensitive = true
}

resource "local_file" "grafana_env" {
  filename = "${path.module}/../.env"

  content = <<EOF
AWS_ACCESS_KEY_ID=${aws_iam_access_key.grafana_key.id}
AWS_SECRET_ACCESS_KEY=${aws_iam_access_key.grafana_key.secret}
EOF
}