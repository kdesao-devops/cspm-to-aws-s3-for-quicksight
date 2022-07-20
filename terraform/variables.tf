variable "aws_region" {
  description = "AWS region for all resources."

  type    = string
  default = "ca-central-1"
}

# Lambda Environment Variables
variable "cloudguard_api_endpoint" {
  description = "CloudGuard API Endpoint"

  type    = string
  default = "api.cace1.dome9.com/v2"
}

variable "cloudguard_api_page_size" {
  description = "CloudGuard API PageSize"

  type    = number
  default = 1000
}

# Values for SSM Parameter Store
variable "cloudguard_api_keys_parameter" {
  description = "CloudGuard API Keys"

  type = string
}