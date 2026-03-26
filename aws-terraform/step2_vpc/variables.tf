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

# Public Subnet CIDR（例：10.0.1.0/24）

variable "public_subnet_cidr" {

  type = string

  default = "10.0.1.0/24"

}

# Private Subnet CIDR（例：10.0.2.0/24）

variable "private_subnet_cidr" {

  type = string

  default = "10.0.2.0/24"

}