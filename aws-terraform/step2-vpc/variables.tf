variable "project_name" {
  type    = string
  default = "tf-vpc-public-ec2"
}

# EC2のKey Pair名（例：tf-learning-key）
variable "key_name" {
  type = string
}

# 自分のグローバルIP/32（例：203.0.113.10/32）
variable "my_ip_cidr" {
  type = string
}