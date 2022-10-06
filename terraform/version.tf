# Global Configuration
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.24.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2.0"
    }
    keycloak = {
      source  = "mrparkers/keycloak"
      version = ">= 3.0.0"
    }
  }

  required_version = "~> 1.0"
}
