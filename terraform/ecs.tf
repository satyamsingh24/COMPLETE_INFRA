# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "${var.project_name}-cluster"
    Environment = var.environment
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7
}

# ECS Task Definition - sab containers ek saath
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = "2048"
  memory                   = "3072"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    # MySQL Container
    {
      name      = "mysql"
      image     = "mysql:8.0"
      essential = false
      
      environment = [
        { name = "MYSQL_ROOT_PASSWORD", value = "root" },
        { name = "MYSQL_DATABASE",      value = "mydb" }
      ]

      mountPoints = [{
        sourceVolume  = "mysql-data"
        containerPath = "/var/lib/mysql"
        readOnly      = false
      }]

      healthCheck = {
        command     = ["CMD", "mysqladmin", "ping", "-h", "localhost", "-uroot", "-proot"]
        interval    = 10
        timeout     = 5
        retries     = 5
        startPeriod = 30
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "mysql"
        }
      }
    },

    # Redis Container
    {
      name      = "redis"
      image     = "redis:alpine"
      essential = false

      healthCheck = {
        command     = ["CMD", "redis-cli", "ping"]
        interval    = 10
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "redis"
        }
      }
    },

    # Backend Container
    {
      name      = "backend"
      image     = "${aws_ecr_repository.backend.repository_url}:latest"
      essential = true

      portMappings = [
        { containerPort = 8085, protocol = "tcp" },
        { containerPort = 8086, protocol = "tcp" }
      ]

      environment = [
        { name = "SPRING_DATASOURCE_URL",      value = "jdbc:mysql://localhost:3306/mydb" },
        { name = "SPRING_DATASOURCE_USERNAME",  value = "root" },
        { name = "SPRING_DATASOURCE_PASSWORD",  value = "root" },
        { name = "SPRING_REDIS_HOST",           value = "localhost" },
        { name = "SPRING_REDIS_PORT",           value = "6379" }
      ]

      dependsOn = [
        { containerName = "mysql", condition = "HEALTHY" },
        { containerName = "redis", condition = "HEALTHY" }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8086/actuator/health || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 60
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "backend"
        }
      }
    },

    # Nginx Container
    {
      name      = "nginx"
      image     = "${aws_ecr_repository.nginx.repository_url}:latest"
      essential = true

      portMappings = [
        { containerPort = 80, protocol = "tcp" }
      ]

      dependsOn = [
        { containerName = "backend", condition = "HEALTHY" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "nginx"
        }
      }
    },

    # Prometheus Container
    {
      name      = "prometheus"
      image     = "prom/prometheus:v2.47.0"
      essential = false

      portMappings = [
        { containerPort = 9090, protocol = "tcp" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "prometheus"
        }
      }
    },

    # Grafana Container
    {
      name      = "grafana"
      image     = "grafana/grafana:10.2.0"
      essential = false

      portMappings = [
        { containerPort = 3000, protocol = "tcp" }
      ]

      environment = [
        { name = "GF_SECURITY_ADMIN_USER",     value = "admin" },
        { name = "GF_SECURITY_ADMIN_PASSWORD",  value = "admin123" },
        { name = "GF_AWS_DEFAULT_REGION",       value = var.aws_region }
      ]

      mountPoints = [{
        sourceVolume  = "grafana-data"
        containerPath = "/var/lib/grafana"
        readOnly      = false
      }]

      dependsOn = [
        { containerName = "prometheus", condition = "START" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "grafana"
        }
      }
    }
  ])

  # Volumes for persistent data
  volume {
    name = "mysql-data"
  }

  volume {
    name = "grafana-data"
  }

  tags = {
    Name = "${var.project_name}-task"
  }
}

# ECS Service
resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "EC2"

  network_configuration {
    subnets         = [aws_subnet.public.id, aws_subnet.public2.id]
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.nginx.arn
    container_name   = "nginx"
    container_port   = 80
  }

  depends_on = [
    aws_lb_listener.app,
    aws_cloudwatch_log_group.ecs,
    aws_iam_role_policy_attachment.ecs_execution_policy
  ]

  tags = {
    Name = "${var.project_name}-service"
  }
}