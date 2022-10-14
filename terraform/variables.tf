variable "aws_region" {
  description = "AWS region for all resources."

  type    = string
  default = "ca-central-1"
}

# Management account access variable
variable "AWS_MANAG_ACCESS_KEY_ID" {
  description = "(Management account key ID. Environment variable syntax: export TF_VAR_AWS_MANAG_ACCESS_KEY_ID=secret)"
  type        = string
}

variable "AWS_MANAG_SECRET_ACCESS_KEY" {
  description = "(Management account access key. Environment variable syntax: export TF_VAR_AWS_MANAG_SECRET_ACCESS_KEY=secret)"
  type        = string
}

variable "AWS_MANAG_SESSION_TOKEN" {
  description = "(Management account token. Environment variable syntax: export TF_VAR_AWS_MANAG_SESSION_TOKEN=secret)"
  type        = string
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
  description = "CloudGuard API Keys. Environment variable syntax: export TF_VAR_cloudguard_api_keys_parameter=secret"

  type = string
}

################
## SSO Config ##
################

# Keycloak provider configuration
variable "kc_base_url" {
  description = "Base URL for Keycloak"
}

variable "kc_realm" {
  description = "realm name for Keycloak"
}

variable "kc_terraform_auth_client_id" {
  description = "Keycloal progamatic user name"
}

variable "kc_openid_client_id" {
  description = "Client ID of the AWS provider in Keycloak (This isn't the same as the uniaue client-id that's why we use the data block)"
}


variable "lz_portal_cloudfront_url" {
  description = "Url of the lz identification app Cloudfront distribution. Temporary until we use the overlay repository"
}

# User right management
variable "reader_list" {
  description = "List of user allowed to create a Reader user on Quicksight"
  type        = list(string)
}

variable "author_list" {
  description = "List of user allowed to create a Author user on Quicksight"
  type        = list(string)
}

variable "admin_list" {
  description = "List of user allowed to create a Admin user on Quicksight"
  type        = list(string)
}