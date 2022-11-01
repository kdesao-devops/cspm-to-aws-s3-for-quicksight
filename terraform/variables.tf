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

variable "cloud_guard_api_key_parameter_store_name" {
  description = "Name of the pre-created SSM Parameter containing the CloudGuard API Keys for the data_importer_lambda"
  type = string

  default = "/cloudguard_dashboard/cloudguard_api_keys"
}

################
## SSO Config ##
################
# Keycloak provider configuration
variable "kc_base_url" {
  default     = "https://oidc.gov.bc.ca/auth"
  description = "Base URL for Keycloak"
}

variable "kc_realm" {
  default     = "umafubc9"
  description = "realm name for Keycloak"
}

variable "kc_terraform_auth_client_id" {
  default     = "terraform"
  description = "Keycloal progamatic user name"
}

variable "kc_openid_client_id" {
  default     = "urn:amazon:webservices"
  description = "Client ID of the AWS provider in Keycloak (This isn't the same as the uniaue client-id that's why we use the data block)"
}


variable "lz_portal_cloudfront_url" {
  default     = "https://d1kb6br25oqacj.cloudfront.net/test"
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