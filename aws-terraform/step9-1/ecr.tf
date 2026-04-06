############################################################
# ECR: Repository
############################################################

resource "aws_ecr_repository" "app" {
  name = var.ecr_repository_name

  # まずは既存に寄せる（差分を出しにくくする）
  image_tag_mutability = "MUTABLE"

  force_delete = true

  tags = local.common_tags
}