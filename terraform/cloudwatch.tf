# ============================================
# CloudWatch Dashboard - Modern Look
# ============================================
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [

      # ── TITLE ──────────────────────────────
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# 🚀 ${var.project_name} - Production Dashboard\n> Real-time monitoring | EC2 · ALB · ECR"
        }
      },

      # ── EC2 CPU - Number Widget ─────────────
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 6
        height = 4
        properties = {
          title  = "🖥️ EC2 CPU %"
          view   = "singleValue"
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.jenkins.id]
          ]
          region = var.aws_region
        }
      },

      # ── ALB Request Count - Number ──────────
      {
        type   = "metric"
        x      = 6
        y      = 1
        width  = 6
        height = 4
        properties = {
          title  = "🌐 Total Requests"
          view   = "singleValue"
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.app.arn_suffix]
          ]
          region = var.aws_region
        }
      },

      # ── ALB Healthy Hosts - Number ──────────
      {
        type   = "metric"
        x      = 12
        y      = 1
        width  = 6
        height = 4
        properties = {
          title  = "✅ Healthy Hosts"
          view   = "singleValue"
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_lb_target_group.nginx.arn_suffix, "LoadBalancer", aws_lb.app.arn_suffix]
          ]
          region = var.aws_region
        }
      },

      # ── ALB 5XX Errors - Number ─────────────
      {
        type   = "metric"
        x      = 18
        y      = 1
        width  = 6
        height = 4
        properties = {
          title  = "❌ 5XX Errors"
          view   = "singleValue"
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", aws_lb.app.arn_suffix]
          ]
          region = var.aws_region
        }
      },

      # ── EC2 CPU - Line Chart ────────────────
      {
        type   = "metric"
        x      = 0
        y      = 5
        width  = 12
        height = 6
        properties = {
          title  = "🖥️ EC2 CPU Utilization (Line)"
          view   = "timeSeries"
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.jenkins.id]
          ]
          yAxis = {
            left = { min = 0, max = 100 }
          }
          annotations = {
            horizontal = [{
              label = "Warning (80%)"
              value = 80
              color = "#ff7f0e"
            }]
          }
          region = var.aws_region
        }
      },

      # ── EC2 Network - Area Chart ────────────
      {
        type   = "metric"
        x      = 12
        y      = 5
        width  = 12
        height = 6
        properties = {
          title  = "📡 EC2 Network In/Out (Area)"
          view   = "timeSeries"
          stacked = true
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/EC2", "NetworkIn",  "InstanceId", aws_instance.jenkins.id, { label = "Network In",  color = "#2ca02c" }],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.jenkins.id, { label = "Network Out", color = "#1f77b4" }]
          ]
          region = var.aws_region
        }
      },

      # ── ALB Requests - Bar Chart ────────────
      {
        type   = "metric"
        x      = 0
        y      = 11
        width  = 12
        height = 6
        properties = {
          title  = "🌐 ALB Request Count (Bar)"
          view   = "bar"
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.app.arn_suffix, { label = "Requests", color = "#1f77b4" }]
          ]
          region = var.aws_region
        }
      },

      # ── ALB Response Time - Line Chart ──────
      {
        type   = "metric"
        x      = 12
        y      = 11
        width  = 12
        height = 6
        properties = {
          title  = "⚡ ALB Response Time (ms)"
          view   = "timeSeries"
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.app.arn_suffix, { label = "Response Time", color = "#9467bd" }]
          ]
          annotations = {
            horizontal = [{
              label = "Slow (5s)"
              value = 5
              color = "#d62728"
            }]
          }
          region = var.aws_region
        }
      },

      # ── ALB 4XX/5XX - Stacked Bar ───────────
      {
        type   = "metric"
        x      = 0
        y      = 17
        width  = 12
        height = 6
        properties = {
          title  = "🚨 ALB Error Codes (Stacked)"
          view   = "bar"
          stacked = true
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_ELB_4XX_Count", "LoadBalancer", aws_lb.app.arn_suffix, { label = "4XX", color = "#ff7f0e" }],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", aws_lb.app.arn_suffix, { label = "5XX", color = "#d62728" }]
          ]
          region = var.aws_region
        }
      },

      # ── ALB Healthy vs Unhealthy - Line ─────
      {
        type   = "metric"
        x      = 12
        y      = 17
        width  = 12
        height = 6
        properties = {
          title  = "🏥 ALB Healthy vs Unhealthy Hosts"
          view   = "timeSeries"
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount",   "TargetGroup", aws_lb_target_group.nginx.arn_suffix, "LoadBalancer", aws_lb.app.arn_suffix, { label = "Healthy",   color = "#2ca02c" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", aws_lb_target_group.nginx.arn_suffix, "LoadBalancer", aws_lb.app.arn_suffix, { label = "Unhealthy", color = "#d62728" }]
          ]
          region = var.aws_region
        }
      },

      # ── EC2 Status Check - Number ───────────
      {
        type   = "metric"
        x      = 0
        y      = 23
        width  = 8
        height = 4
        properties = {
          title  = "💚 EC2 Status Check"
          view   = "singleValue"
          period = 60
          stat   = "Maximum"
          metrics = [
            ["AWS/EC2", "StatusCheckFailed", "InstanceId", aws_instance.jenkins.id]
          ]
          region = var.aws_region
        }
      },

      # ── ALB Active Connections ───────────────
      {
        type   = "metric"
        x      = 8
        y      = 23
        width  = 8
        height = 4
        properties = {
          title  = "🔗 Active Connections"
          view   = "singleValue"
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "ActiveConnectionCount", "LoadBalancer", aws_lb.app.arn_suffix]
          ]
          region = var.aws_region
        }
      },

      # ── ALB New Connections ──────────────────
      {
        type   = "metric"
        x      = 16
        y      = 23
        width  = 8
        height = 4
        properties = {
          title  = "🆕 New Connections"
          view   = "singleValue"
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "NewConnectionCount", "LoadBalancer", aws_lb.app.arn_suffix]
          ]
          region = var.aws_region
        }
      }
    ]
  })
}

# ============================================
# EC2 Alarms
# ============================================
resource "aws_cloudwatch_metric_alarm" "ec2_cpu_high" {
  alarm_name          = "${var.project_name}-ec2-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "EC2 CPU above 80%"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  dimensions = {
    InstanceId = aws_instance.jenkins.id
  }
}

resource "aws_cloudwatch_metric_alarm" "ec2_cpu_critical" {
  alarm_name          = "${var.project_name}-ec2-cpu-critical"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 95
  alarm_description   = "EC2 CPU above 95% - CRITICAL"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  dimensions = {
    InstanceId = aws_instance.jenkins.id
  }
}

# ============================================
# ALB Alarms
# ============================================
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project_name}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "ALB 5XX errors above 10"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "${var.project_name}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "ALB has unhealthy hosts"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  dimensions = {
    TargetGroup  = aws_lb_target_group.nginx.arn_suffix
    LoadBalancer = aws_lb.app.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_response_time" {
  alarm_name          = "${var.project_name}-alb-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 5
  alarm_description   = "ALB response time above 5 seconds"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
  }
}

# ============================================
# CloudWatch Log Group
# ============================================
resource "aws_cloudwatch_log_group" "docker" {
  name              = "/docker/${var.project_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-docker-logs"
  }
}

# ============================================
# Output
# ============================================
output "cloudwatch_dashboard_url" {
  description = "CloudWatch Dashboard URL"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${var.project_name}-dashboard"
}