# Bootstrap: creates the S3 bucket that holds the *root* module's Terraform state.
#
# Chicken-and-egg: the root module stores its state in S3, but something has to
# create that bucket first. This tiny module does only that, and keeps its own
# state in a local file (bootstrap/terraform.tfstate, gitignored). Run it once:
#
#   ./tf -chdir=bootstrap init
#   ./tf -chdir=bootstrap apply
#
# then copy the printed bucket name into ../backend.hcl.

terraform {
  required_version = "~> 1.16"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.64"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "pinch"
      ManagedBy = "terraform"
    }
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region for the state bucket. Keep it the same as the root module."
  default     = "eu-central-1"
}

# Used only to build a globally unique bucket name (S3 bucket names are global).
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "tfstate" {
  bucket = "pinch-tfstate-${data.aws_caller_identity.current.account_id}"

  # Refuse `terraform destroy` while state files are inside. Remove this line
  # (and empty the bucket) if you really want to tear the bucket down.
  lifecycle {
    prevent_destroy = true
  }
}

# Keep every previous state file, so a bad apply can be rolled back.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# State contains secrets (e.g. the Neon connection string) -> encrypt at rest.
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Belt and braces: this bucket must never be public.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "state_bucket_name" {
  description = "Put this into ../backend.hcl as `bucket = \"...\"`."
  value       = aws_s3_bucket.tfstate.bucket
}
