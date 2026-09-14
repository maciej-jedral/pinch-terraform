# Which Terraform and which providers this module needs, and where state lives.

terraform {
  required_version = "~> 1.16"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.64"
    }
    # Community provider sponsored by Neon: https://neon.com/docs/reference/terraform
    neon = {
      source  = "kislerdm/neon"
      version = "~> 0.18"
    }
  }

  # Remote state in S3 (created by ./bootstrap). The bucket name is supplied at
  # init time from the gitignored backend.hcl (see ./tf), everything else is here.
  # `use_lockfile` = native S3 locking, no DynamoDB table needed (Terraform >= 1.10).
  backend "s3" {
    key          = "pinch/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  # Every resource gets these tags, so the AWS console/billing can group them.
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

# Authenticates via the NEON_API_KEY environment variable (see .env.example).
provider "neon" {}
