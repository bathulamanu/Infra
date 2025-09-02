cd Infra/infra
terraform init
terraform plan -out plan.tfplan
terraform apply "plan.tfplan"
