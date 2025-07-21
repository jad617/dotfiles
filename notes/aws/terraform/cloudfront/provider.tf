provider "aws" {
  region = var.region
}

provider "aws" {
  region = "us-east-1"
  alias  = "us-east-1"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  backend "s3" {
    region  = "ca-central-1"
    encrypt = true
  }

  required_version = ">= 1.8.2"
}
