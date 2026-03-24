# ============================================================
# Grafana Dashboard - Auto Instance ID + ALB
# ============================================================

locals {
  instance_id              = aws_instance.jenkins.id
  alb_arn_suffix           = aws_lb.app.arn_suffix
  target_group_arn_suffix  = aws_lb_target_group.nginx.arn_suffix
}

# ============================================================
# CloudWatch Data Source
# ============================================================
resource "grafana_data_source" "cloudwatch" {
  depends_on = [time_sleep.wait_for_grafana]

  type = "cloudwatch"
  name = "CloudWatch"

  json_data_encoded = jsonencode({
    defaultRegion = var.aws_region
    authType      = "default"   # IAM Role use karega — no keys needed
  })
}

# ============================================================
# Dashboard
# ============================================================
resource "grafana_dashboard" "aws_dashboard" {
  depends_on = [grafana_data_source.cloudwatch]

  config_json = jsonencode({
    title        = "Complete Infra - AWS Dashboard"
    tags         = ["cloudwatch", "ec2", "alb", "logs"]
    timezone     = "browser"
    refresh      = "30s"
    schemaVersion = 36
    time         = { from = "now-3h", to = "now" }

    panels = [

      # ----------------------------------------------------------
      # 1. EC2 CPU Utilization
      # ----------------------------------------------------------
      {
        id      = 1
        title   = "EC2 CPU Utilization"
        type    = "timeseries"
        gridPos = { h = 8, w = 12, x = 0, y = 0 }
        targets = [{
          datasource = "CloudWatch"
          namespace  = "AWS/EC2"
          metricName = "CPUUtilization"
          dimensions = { InstanceId = local.instance_id }
          statistics = ["Average"]
          period     = "60"
          region     = var.aws_region
          refId      = "A"
        }]
        fieldConfig = {
          defaults = {
            unit = "percent"
            color = { mode = "palette-classic" }
            thresholds = {
              steps = [
                { color = "green",  value = null },
                { color = "yellow", value = 60 },
                { color = "red",    value = 80 }
              ]
            }
          }
        }
      },

      # ----------------------------------------------------------
      # 2. EC2 Network In/Out
      # ----------------------------------------------------------
      {
        id      = 2
        title   = "EC2 Network In/Out"
        type    = "timeseries"
        gridPos = { h = 8, w = 12, x = 12, y = 0 }
        targets = [
          {
            datasource = "CloudWatch"
            namespace  = "AWS/EC2"
            metricName = "NetworkIn"
            dimensions = { InstanceId = local.instance_id }
            statistics = ["Average"]
            period     = "60"
            region     = var.aws_region
            refId      = "A"
          },
          {
            datasource = "CloudWatch"
            namespace  = "AWS/EC2"
            metricName = "NetworkOut"
            dimensions = { InstanceId = local.instance_id }
            statistics = ["Average"]
            period     = "60"
            region     = var.aws_region
            refId      = "B"
          }
        ]
        fieldConfig = { defaults = { unit = "bytes" } }
      },

      # ----------------------------------------------------------
      # 3. ALB Request Count
      # ----------------------------------------------------------
      {
        id      = 3
        title   = "ALB Request Count"
        type    = "timeseries"
        gridPos = { h = 8, w = 12, x = 0, y = 8 }
        targets = [{
          datasource = "CloudWatch"
          namespace  = "AWS/ApplicationELB"
          metricName = "RequestCount"
          dimensions = { LoadBalancer = local.alb_arn_suffix }
          statistics = ["Sum"]
          period     = "60"
          region     = var.aws_region
          refId      = "A"
        }]
        fieldConfig = { defaults = { unit = "short" } }
      },

      # ----------------------------------------------------------
      # 4. ALB 5XX Errors
      # ----------------------------------------------------------
      {
        id      = 4
        title   = "ALB 5XX Errors"
        type    = "timeseries"
        gridPos = { h = 8, w = 12, x = 12, y = 8 }
        targets = [{
          datasource = "CloudWatch"
          namespace  = "AWS/ApplicationELB"
          metricName = "HTTPCode_ELB_5XX_Count"
          dimensions = { LoadBalancer = local.alb_arn_suffix }
          statistics = ["Sum"]
          period     = "60"
          region     = var.aws_region
          refId      = "A"
        }]
        fieldConfig = {
          defaults = {
            unit  = "short"
            color = { fixedColor = "red", mode = "fixed" }
          }
        }
      },

      # ----------------------------------------------------------
      # 5. ALB Target Response Time
      # ----------------------------------------------------------
      {
        id      = 5
        title   = "ALB Target Response Time"
        type    = "timeseries"
        gridPos = { h = 8, w = 12, x = 0, y = 16 }
        targets = [{
          datasource = "CloudWatch"
          namespace  = "AWS/ApplicationELB"
          metricName = "TargetResponseTime"
          dimensions = { LoadBalancer = local.alb_arn_suffix }
          statistics = ["Average"]
          period     = "60"
          region     = var.aws_region
          refId      = "A"
        }]
        fieldConfig = { defaults = { unit = "s" } }
      },

      # ----------------------------------------------------------
      # 6. EC2 Disk Read/Write
      # ----------------------------------------------------------
      {
        id      = 6
        title   = "EC2 Disk Read/Write"
        type    = "timeseries"
        gridPos = { h = 8, w = 12, x = 12, y = 16 }
        targets = [
          {
            datasource = "CloudWatch"
            namespace  = "AWS/EC2"
            metricName = "DiskReadBytes"
            dimensions = { InstanceId = local.instance_id }
            statistics = ["Average"]
            period     = "60"
            region     = var.aws_region
            refId      = "A"
          },
          {
            datasource = "CloudWatch"
            namespace  = "AWS/EC2"
            metricName = "DiskWriteBytes"
            dimensions = { InstanceId = local.instance_id }
            statistics = ["Average"]
            period     = "60"
            region     = var.aws_region
            refId      = "B"
          }
        ]
        fieldConfig = { defaults = { unit = "bytes" } }
      },

      # ----------------------------------------------------------
      # 7. ALB Healthy Hosts
      # ----------------------------------------------------------
      {
        id      = 7
        title   = "ALB Healthy Hosts"
        type    = "stat"
        gridPos = { h = 4, w = 6, x = 0, y = 24 }
        targets = [{
          datasource = "CloudWatch"
          namespace  = "AWS/ApplicationELB"
          metricName = "HealthyHostCount"
          dimensions = {
            LoadBalancer = local.alb_arn_suffix
            TargetGroup  = local.target_group_arn_suffix
          }
          statistics = ["Average"]
          period     = "60"
          region     = var.aws_region
          refId      = "A"
        }]
        fieldConfig = {
          defaults = {
            unit  = "short"
            color = { fixedColor = "green", mode = "fixed" }
            thresholds = {
              steps = [
                { color = "red",   value = null },
                { color = "green", value = 1 }
              ]
            }
          }
        }
        options = {
          reduceOptions = { calcs = ["lastNotNull"] }
          colorMode     = "background"
        }
      },

      # ----------------------------------------------------------
      # 8. Unhealthy Hosts
      # ----------------------------------------------------------
      {
        id      = 8
        title   = "Unhealthy Hosts"
        type    = "stat"
        gridPos = { h = 4, w = 6, x = 6, y = 24 }
        targets = [{
          datasource = "CloudWatch"
          namespace  = "AWS/ApplicationELB"
          metricName = "UnHealthyHostCount"
          dimensions = {
            LoadBalancer = local.alb_arn_suffix
            TargetGroup  = local.target_group_arn_suffix
          }
          statistics = ["Average"]
          period     = "60"
          region     = var.aws_region
          refId      = "A"
        }]
        fieldConfig = {
          defaults = {
            unit = "short"
            thresholds = {
              steps = [
                { color = "green", value = null },
                { color = "red",   value = 1 }
              ]
            }
          }
        }
        options = {
          reduceOptions = { calcs = ["lastNotNull"] }
          colorMode     = "background"
        }
      },

      # ----------------------------------------------------------
      # 9. Application Logs (Backend)
      # ----------------------------------------------------------
      {
        id      = 9
        title   = "🪵 Application Logs (Backend)"
        type    = "logs"
        gridPos = { h = 10, w = 24, x = 0, y = 28 }
        targets = [{
          datasource  = "CloudWatch"
          dimensions  = {}
          expression  = "fields @timestamp, @message | sort @timestamp desc | limit 200"
          id          = "backend_logs"
          logGroups   = [{
            arn  = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/${var.project_name}/backend:*"
            name = "/${var.project_name}/backend"
          }]
          queryMode   = "Logs"
          region      = var.aws_region
          refId       = "A"
        }]
        options = {
          showTime           = true
          wrapLogMessage     = true
          enableLogDetails   = true
          sortOrder          = "Descending"
          dedupStrategy      = "none"
        }
      },

      # ----------------------------------------------------------
      # 10. Nginx Access Logs
      # ----------------------------------------------------------
      {
        id      = 10
        title   = "🪵 Nginx Access Logs"
        type    = "logs"
        gridPos = { h = 10, w = 24, x = 0, y = 38 }
        targets = [{
          datasource  = "CloudWatch"
          dimensions  = {}
          expression  = "fields @timestamp, @message | sort @timestamp desc | limit 200"
          id          = "nginx_logs"
          logGroups   = [{
            arn  = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/${var.project_name}/nginx:*"
            name = "/${var.project_name}/nginx"
          }]
          queryMode   = "Logs"
          region      = var.aws_region
          refId       = "A"
        }]
        options = {
          showTime           = true
          wrapLogMessage     = true
          enableLogDetails   = true
          sortOrder          = "Descending"
          dedupStrategy      = "none"
        }
      },

      # ----------------------------------------------------------
      # 11. EC2 System Logs
      # ----------------------------------------------------------
      {
        id      = 11
        title   = "🪵 EC2 System Logs"
        type    = "logs"
        gridPos = { h = 10, w = 24, x = 0, y = 48 }
        targets = [{
          datasource  = "CloudWatch"
          dimensions  = {}
          expression  = "fields @timestamp, @message | sort @timestamp desc | limit 200"
          id          = "system_logs"
          logGroups   = [{
            arn  = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/${var.project_name}/system:*"
            name = "/${var.project_name}/system"
          }]
          queryMode   = "Logs"
          region      = var.aws_region
          refId       = "A"
        }]
        options = {
          showTime           = true
          wrapLogMessage     = true
          enableLogDetails   = true
          sortOrder          = "Descending"
          dedupStrategy      = "none"
        }
      }

    ] # panels end
  })
}
