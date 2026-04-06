############################################################
# IAM: ECS Task Execution Role
# - ECSがECRからイメージpull / CloudWatch Logsへログ送信するためのロール
############################################################

resource "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRole"

  # 既存ロールをimportする前提なので、ここは「現状と一致」させる。
  # まずは assume role policy を ECS Tasks 用で固定してOK。
  assume_role_policy = jsonencode({
    Version = "2008-10-17"
    Statement = [
      {
        Sid    = ""
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# AWS管理ポリシー（まずはこれでOK。ログ出力やECR pullの基本権限）
resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}