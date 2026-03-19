resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  tags = {
    Name = "${var.project_name}-ecr"
  }
}

resource "aws_ecr_repository" "backend" {
  name                 = "${var.project_name}-app-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  tags = {
    Name = "${var.project_name}-ecr-backend"
  }
}

resource "aws_ecr_repository" "nginx" {
  name                 = "${var.project_name}-app-nginx"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  tags = {
    Name = "${var.project_name}-ecr-nginx"
  }
}
