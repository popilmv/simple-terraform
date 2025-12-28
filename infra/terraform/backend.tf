terraform {
  backend "s3" {
    bucket         = "simple-app-tfstate-eu-central-1"
    key            = "simple-app/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "simple-app-tf-locks"
    encrypt        = true
  }
}
