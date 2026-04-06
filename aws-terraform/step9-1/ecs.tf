############################################################
# ECS: Cluster
############################################################

resource "aws_ecs_cluster" "main" {
  name = var.ecs_cluster_name

  configuration {
    execute_command_configuration {
      logging = "DEFAULT"
    }
  }

  tags = local.common_tags
}