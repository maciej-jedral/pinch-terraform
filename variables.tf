# Inputs. Values come from terraform.tfvars (gitignored) - see terraform.tfvars.example.

variable "project_name" {
  type        = string
  description = "Prefix for resource names and the Project tag."
  default     = "pinch"
}

variable "aws_region" {
  type        = string
  description = "AWS region for all resources."
  default     = "eu-central-1"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type. t4g.* are arm64 (Graviton) - cheaper and free-tier eligible on Free-plan accounts."
  default     = "t4g.micro"
}

variable "ssh_public_key" {
  type        = string
  description = "Contents of the SSH public key that may log in as `ubuntu` (e.g. `cat ~/.ssh/pinch-aws.pub`)."
}

variable "deploy_ssh_public_key" {
  type        = string
  description = "Public half of the key pinch-backend's GitHub Actions workflow uses to SSH in as `ubuntu` (e.g. `cat ~/.ssh/pinch-deploy.pub`). Private half lives only in the GitHub `production` environment."
}

variable "budget_email" {
  type        = string
  description = "Address that receives AWS Budgets alerts. AWS sends a confirmation mail that must be accepted."
}

variable "budget_limit_usd" {
  type        = number
  description = "Monthly gross-usage budget in USD (credits are NOT subtracted, so this tracks real consumption)."
  default     = 15
}

variable "neon_org_id" {
  type        = string
  description = "Neon organisation id (Neon console -> Settings -> General, looks like org-xxxx-xxxx-12345678)."
}

variable "neon_region_id" {
  type        = string
  description = "Neon region. https://neon.com/docs/introduction/regions"
  default     = "aws-eu-central-1"
}

variable "neon_pg_version" {
  type        = number
  description = "Postgres major version for the Neon project. Local dev runs 18."
  default     = 18
}
