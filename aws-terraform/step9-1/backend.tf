terraform {
  backend "s3" {
    bucket         = "infra-learning-tfstate-20260407" # <- 作ったS3に置き換え
    key            = "step9-1/terraform.tfstate"       # <- stateファイルのパス（好みでOK）
    region         = "ap-northeast-1"
    dynamodb_table = "infra-learning-terraform-lock" # <- 作ったDynamoDBに置き換え
    encrypt        = true
  }
}