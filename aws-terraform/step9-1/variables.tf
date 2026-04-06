variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Tag prefix"
  type        = string
  default     = "infra-learning"
}

variable "log_group_name" {
  description = "CloudWatch Logs log group name for ECS awslogs driver"
  type        = string
  default     = "/ecs/infra-learning/health-app"
}

variable "log_retention_in_days" {
  description = "Retention days for CloudWatch Logs"
  type        = number
  default     = 1
}

variable "ecr_repository_name" {
  description = "ECR repository name (must match existing repo)"
  type        = string
  default     = "health-app"
}

variable "ecs_cluster_name" {
  description = "ECS cluster name (must match existing cluster)"
  type        = string
  default     = "infra-learning"
}

variable "ecs_task_family" {
  description = "ECS task definition family"
  type        = string
  default     = "health-app-task"
}

variable "ecs_service_name" {
  description = "ECS service name"
  type        = string
  default     = "health-app-svc"
}

variable "ecs_desired_count" {
  description = "Desired task count (match existing first)"
  type        = number
  default     = 0
}

variable "ecs_subnet_ids" {
  description = "Subnets for awsvpc configuration"
  type        = list(string)
  default = [
    "subnet-02667b8e8e160e486",
    "subnet-053b33ae31aa46588",
    "subnet-04b699aa01cb038cd",
  ]
}

variable "ecs_security_group_ids" {
  description = "Security groups for awsvpc configuration"
  type        = list(string)
  default     = ["sg-01c2f879347ae8a64"]
}

variable "ecs_assign_public_ip" {
  description = "Assign public IP"
  type        = bool
  default     = true
}