terraform {
  required_version = ">= 1.5"

  backend "s3" {
    bucket         = "pi-credit-terraform-state-463932052716" # create this bucket first or change
    key            = "infra/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "pi-credit-tf-locks"                  
    encrypt        = true
  }
}
