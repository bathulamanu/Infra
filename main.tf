locals {
  project        = var.project
  short_project  = substr(var.project, 0, 24)
  aws_account_id = "463932052716"
}

data "aws_availability_zones" "available" {
  state = "available"
}

# ---------- VPC ----------
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = { Name = "${local.project}-vpc" }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "${local.project}-public-${count.index+1}" }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "${local.project}-private-${count.index+1}" }
}

# ---------- Internet Gateway & Routes ----------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "${local.project}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${local.project}-public-rt" }
}

resource "aws_route_table_association" "public_assoc" {
  count         = length(aws_subnet.public)
  subnet_id     = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway
resource "aws_eip" "nat" {
  vpc = true
  tags = { Name = "${local.project}-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags = { Name = "${local.project}-nat" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "${local.project}-private-rt" }
}

resource "aws_route_table_association" "private_assoc" {
  count         = length(aws_subnet.private)
  subnet_id     = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ---------- Security Groups ----------
resource "aws_security_group" "alb" {
  name        = "${local.project}-alb-sg"
  description = "Allow HTTP/HTTPS from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.project}-alb-sg" }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.project}-ecs-sg"
  description = "Allow traffic from ALB only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Allow ALB -> app"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.project}-ecs-sg" }
}

resource "aws_security_group" "rds" {
  name        = "${local.project}-rds-sg"
  description = "Allow Postgres only from ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.project}-rds-sg" }
}

resource "aws_security_group" "bastion_sg" {
  name        = "${local.project}-bastion-sg"
  description = "Allow SSH from admin IP"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.project}-bastion-sg" }
}

# ---------- ECR ----------
resource "aws_ecr_repository" "app" {
  name = "${local.project}-app"
  image_scanning_configuration { scan_on_push = true }
  tags = { Name = local.project }
}

# ---------- ECS Cluster ----------
resource "aws_ecs_cluster" "cluster" {
  name = "${local.project}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ---------- IAM Roles & Policies ----------
data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${local.project}-ecs-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

resource "aws_iam_role_policy_attachment" "exec_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_ssm_read" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}

# ---------- Application Load Balancer ----------
resource "aws_lb" "alb" {
  name               = "${local.project}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
  tags = { Name = "${local.project}-alb" }
}

resource "aws_lb_target_group" "tg" {
  name     = "${local.project}-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/healthz"
    port                = "5000"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200-399"
  }

  tags = { Name = "${local.project}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# ---------- RDS Postgres ----------
resource "aws_db_subnet_group" "rds" {
  name       = "${local.project}-rds-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  tags = { Name = "${local.project}-rds-sng" }
}

resource "aws_db_instance" "postgres" {
  identifier              = "${local.project}-db"
  engine                  = "postgres"
  engine_version          = "15.3"
  instance_class          = "db.t3.micro"
  name                    = "appdb"
  username                = var.db_username
  password                = var.db_password
  allocated_storage       = 20
  storage_encrypted       = true
  skip_final_snapshot     = true
  vpc_security_group_ids  = [aws_security_group.rds.id]
  db_subnet_group_name    = aws_db_subnet_group.rds.name
  backup_retention_period = 7
  multi_az                = false
  publicly_accessible     = false
  tags = { Name = "${local.project}-db" }

  # Wait for endpoint
  lifecycle {
    ignore_changes = [password] # allow password rotation outside of terraform if needed
  }
}

# ---------- SSM Parameters for DB (so container reads from SSM secrets) ----------
resource "aws_ssm_parameter" "db_username" {
  name  = "/${local.project}/db/username"
  type  = "String"
  value = var.db_username
  tags  = { project = local.project }
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/${local.project}/db/password"
  type  = "SecureString"
  value = var.db_password
  tags  = { project = local.project }
}

resource "aws_ssm_parameter" "db_name" {
  name  = "/${local.project}/db/name"
  type  = "String"
  value = aws_db_instance.postgres.name
  tags  = { project = local.project }
}

resource "aws_ssm_parameter" "db_host" {
  name  = "/${local.project}/db/host"
  type  = "String"
  value = aws_db_instance.postgres.address
  tags  = { project = local.project }
}

# ---------- ECS Task Definition (Fargate) ----------
# NOTE: image uses ECR repo; CI pipeline will push image with specific tag.
resource "aws_ecs_task_definition" "app" {
  family                   = "${local.project}-task"
  cpu                      = "512"
  memory                   = "1024"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "${aws_ecr_repository.app.repository_url}:latest" # pipeline should push tag with actual sha
      essential = true
      portMappings = [{ containerPort = 5000, hostPort = 5000, protocol = "tcp" }]
      secrets = [
        { name = "DB_USER", valueFrom = aws_ssm_parameter.db_username.arn },
        { name = "DB_PASSWORD", valueFrom = aws_ssm_parameter.db_password.arn },
        { name = "DB_NAME", valueFrom = aws_ssm_parameter.db_name.arn },
        { name = "DB_HOST", valueFrom = aws_ssm_parameter.db_host.arn }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/${local.project}"
          awslogs-region        = var.region
          awslogs-stream-prefix = "app"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = "${local.project}-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = aws_subnet.private[*].id
    security_groups = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg.arn
    container_name   = "app"
    container_port   = 5000
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  depends_on = [aws_lb_listener.http]
  tags       = { Name = "${local.project}-service" }
}

# ---------- Bastion Host ----------
resource "aws_key_pair" "bastion_key" {
  key_name   = "${local.project}-bastion-key"
  public_key = file(var.bastion_public_key_path)
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public[0].id
  key_name               = aws_key_pair.bastion_key.key_name
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  tags = { Name = "${local.project}-bastion" }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["137112412989"] # Amazon
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"]
  }
}

# ---------- CloudWatch Log Group & Dashboard ----------
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${local.project}"
  retention_in_days = 30
}

resource "aws_cloudwatch_dashboard" "dashboard" {
  dashboard_name = "${local.project}-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric",
        x = 0, y = 0, width = 6, height = 6,
        properties = {
          metrics = [[ "AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.cluster.name ]]
          period = 300
          stat = "Average"
          region = var.region
          title = "ECS CPU"
        }
      },
      {
        type = "metric",
        x = 6, y = 0, width = 6, height = 6,
        properties = {
          metrics = [[ "AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.postgres.id ]]
          period = 300
          stat = "Average"
          region = var.region
          title = "RDS Connections"
        }
      }
    ]
  })
}

# ---------- Outputs ----------
output "alb_dns" {
  value       = aws_lb.alb.dns_name
  description = "Dnd"
}

output "ecr_repo_url" {
  value       = 463932052716.dkr.ecr.eu-north-1.amazonaws.com/my-nginx
  description = "ECR repository URL for app images"
}

output "ecs_cluster_name" {
  value       = aws_ecs_cluster
  description = "ECS cluster name"
}

output "rds_endpoint" {
  value       = RDs
  description = "RDS endpoint (internal)"
}
