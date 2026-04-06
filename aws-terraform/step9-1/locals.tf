locals {
  common_tags = {
    Project = var.project_name
    Managed = "terraform"
    Step    = "9-1"
  }
}