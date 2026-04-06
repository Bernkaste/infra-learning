############################################################
# ECS: Task Definition
############################################################

resource "aws_ecs_task_definition" "app" {
  family                   = "health-app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  cpu    = "256"
  memory = "512"

  # まずは現物(taskdef.json)に完全一致させる
  execution_role_arn = "arn:aws:iam::077024045672:role/ecsTaskExecutionRole"

  container_definitions = jsonencode([
    {
      name           = "health-app"
      image          = "077024045672.dkr.ecr.ap-northeast-1.amazonaws.com/health-app:8ff8950c76ad758bb4412fc785653ccba25bc44e"
      cpu            = 0
      essential      = true
      environment    = []
      mountPoints    = []
      volumesFrom    = []
      systemControls = []

      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/infra-learning/health-app"
          awslogs-region        = "ap-northeast-1"
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = local.common_tags
}