variable "project" {
  description = "Project short name"
  type        = string
  default     = "pi-credit-devops-hiring-2025"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  type    = list(string)
  default = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "db_username" {
  type    = string
  default = "appuser"
}

# recommended: set this in terraform.tfvars or pass via CLI; it's used to populate SSM SecureString
variable "db_password" {
  type    = string
  default = "PASSWD"
}

variable "bastion_public_key_path" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}

variable "my_ip_cidr" {
  type    = string
  default = "0.0.0.0/0" # replace with "X.Y.Z.W/32" (your IP) before applying
}
