terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 4.60.0"
    }
  }

  /* backend "s3" {
    
  } */
}

provider "aws" {
  region     =  var.aws_region
  access_key = var.aws_access_id
  secret_key = var.aws_secret_key
}

