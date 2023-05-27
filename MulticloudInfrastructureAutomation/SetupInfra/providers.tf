terraform {
  required_providers {
    azurerm = {                       // it's a map
      source  = "hashicorp/azurerm"
      version = "3.54.0"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "4.65.0"
    }
  }

  backend "s3" {
    
  }
}

provider "aws" {
  region = var.awsregion
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

provider "azurerm" {
    features {}
    subscription_id = var.azure_subscription_id
    tenant_id       = var.azure_tenant_id
    client_id       = var.azure_client_id
    client_secret   = var.azure_client_secret
  
}