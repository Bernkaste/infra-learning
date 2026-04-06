############################################################
# ECS: Service (ALBなし)
############################################################

resource "aws_ecs_service" "app" {
  name    = var.ecs_service_name
  cluster = aws_ecs_cluster.main.id

  launch_type      = "FARGATE"
  platform_version = "LATEST"
  desired_count    = var.ecs_desired_count
  task_definition  = aws_ecs_task_definition.app.arn

  enable_ecs_managed_tags       = true
  availability_zone_rebalancing = "ENABLED"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.ecs_subnet_ids
    security_groups  = var.ecs_security_group_ids
    assign_public_ip = var.ecs_assign_public_ip
  }

  tags = local.common_tags
}