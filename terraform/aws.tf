locals {
  core_accounts      = { for account in module.lz_info.core_accounts : account.name => account }
  operations_account = local.core_accounts["Operations"]
}

# Account that has access to the organization root to get the account list
provider "aws" {
  alias  = "operation"
  region = var.aws_region
  assume_role {
    role_arn     = "arn:aws:iam::${local.operations_account.id}:role/AWSCloudFormationStackSetExecutionRole"
    session_name = "slz-terraform-automation"
  }
}

# Data Gathering
module "lz_info" {
  source = "github.com/BCDevOps/terraform-aws-sea-organization-info"
  providers = {
    aws = aws
  }
}


data "aws_caller_identity" "current" {
}

data "aws_caller_identity" "operation" {
  provider = aws.operation
}

data "aws_region" "current" {}

data "aws_region" "operation" {
  provider = aws.operation
}

# S3 Bucket for Lambda asset
resource "aws_s3_bucket" "cloudguard_dashboard_lambda_bucket" {
  provider      = aws.operation
  bucket        = "cloudguard-dashboard-lambda-${data.aws_caller_identity.operation.account_id}-${data.aws_region.operation.name}"
  acl           = "private"
  force_destroy = false
}

# S3 Bucket for storing CloudGuard data
resource "aws_s3_bucket" "cloudguard_dashboard_data_bucket" {
  provider      = aws.operation
  bucket        = "cloudguard-dashboard-data-${data.aws_caller_identity.operation.account_id}-${data.aws_region.operation.name}"
  acl           = "private"
  force_destroy = false
}

# Additionnal right for the lambda exuction
resource "aws_iam_policy" "cloudguard_dashboard_lambda_policies" {
  provider = aws.operation
  name     = "CloudGuardDashboardLambdaPermissions"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "AllowAccessToCloudGuardDataBucket"
        Action = [
          "s3:GetObject",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload",
          "s3:CreateBucket",
          "s3:PutObject",
          "s3:PutObjectAcl"
        ],
        Resource = [
          "${aws_s3_bucket.cloudguard_dashboard_data_bucket.arn}/*"
        ]
        Effect = "Allow"
      },
      {
        Sid = "AllowUseOfKmsKey"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = [
          "*"
        ]
        Effect = "Allow"
      }
    ]
  })
}


# Install Lambda function dependencies
# Using Terraform to install dependencies. Once a CI/CD mechanism is developed,
# this step could be moved out of Terraform in to the CI/CD flow
#
# CloudGuardDataImporter Lambda artifacts
resource "null_resource" "install_data_importer_lambda_dependencies" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<-EOF
      cd ${path.module}/../lambda/dataImporter/src &&\
      npm install
    EOF
  }
}

data "archive_file" "data_importer_lambda" {
  type = "zip"

  source_dir  = "${path.module}/../lambda/dataImporter"
  output_path = "${path.module}/../dataImporter.zip"
}

resource "aws_s3_bucket_object" "cloudguard_data_importer" {
  provider = aws.operation
  bucket   = aws_s3_bucket.cloudguard_dashboard_lambda_bucket.id

  key    = "cloudguard-data-importer-lambda.zip"
  source = data.archive_file.data_importer_lambda.output_path

  etag = filemd5(data.archive_file.data_importer_lambda.output_path)
}

# CloudGuardDataImporter Lambda role
resource "aws_iam_role" "data_importer_lambda_exec_role" {
  provider = aws.operation
  name     = "CloudGuardDataImporterExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Attach policies
resource "aws_iam_role_policy_attachment" "data_importer_basic_execution_policy" {
  provider   = aws.operation
  role       = aws_iam_role.data_importer_lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "data_importer_parameter_store_readonly_policy" {
  provider   = aws.operation
  role       = aws_iam_role.data_importer_lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}

# Attach the LambdaPermissions IAM policy to DataImporter Lambda Execution Role
resource "aws_iam_role_policy_attachment" "data_importer_lambda_access" {
  provider   = aws.operation
  role       = aws_iam_role.data_importer_lambda_exec_role.name
  policy_arn = aws_iam_policy.cloudguard_dashboard_lambda_policies.arn
}

resource "aws_lambda_function" "data_importer_lambda" {
  provider      = aws.operation
  function_name = "CloudGuardDataImporter"
  description   = "Pull data from CheckPoint CloudGuard for presenting on a dashboard"

  s3_bucket = aws_s3_bucket.cloudguard_dashboard_lambda_bucket.id
  s3_key    = aws_s3_bucket_object.cloudguard_data_importer.key

  runtime     = "nodejs14.x"
  handler     = "src/index.index"
  timeout     = 180
  memory_size = 512

  environment {
    variables = {
      "CLOUDGUARD_API_ENDPOINT"             = var.cloudguard_api_endpoint
      "CLOUDGUARD_API_KEYS_PARAMETER_STORE" = var.cloud_guard_api_key_parameter_store_name
      "CLOUDGUARD_PAGE_SIZE"                = var.cloudguard_api_page_size
      "CLOUDGUARD_DATA_S3_BUCKET_ID"        = aws_s3_bucket.cloudguard_dashboard_data_bucket.id
      "AWS_API_REGION"                      = var.aws_region
    }
  }

  source_code_hash = data.archive_file.data_importer_lambda.output_base64sha256
  role             = aws_iam_role.data_importer_lambda_exec_role.arn
}

# CloudWatch
resource "aws_lambda_permission" "data_importer_allow_execution_from_cloudwatch" {
  provider      = aws.operation
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_importer_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cloudguard_dashboard_eventbridge.arn
}

resource "aws_cloudwatch_event_rule" "cloudguard_dashboard_eventbridge" {
  provider            = aws.operation
  name                = "CloudGuard-Dashboard-data-import"
  description         = "Query CloudGuard API. Used to trigger the CloudGuard-Dashboard Lambda"
  schedule_expression = "cron(0 19 * * ? *)"
  is_enabled          = true
}

resource "aws_cloudwatch_event_target" "cloudguard_dashboard_import_eventbridge_target" {
  provider = aws.operation
  arn      = aws_lambda_function.data_importer_lambda.arn
  rule     = aws_cloudwatch_event_rule.cloudguard_dashboard_eventbridge.name
}

#
#
## DataTransformer Lambda Resources
# CloudGuardDataTransformer Lambda artifacts
resource "null_resource" "install_data_transformer_lambda_dependencies" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<-EOF
      cd ${path.module}/../lambda/dataTransformer/src &&\
      npm install
    EOF
  }
}

data "archive_file" "data_transformer_lambda" {
  type = "zip"

  source_dir  = "${path.module}/../lambda/dataTransformer"
  output_path = "${path.module}/../dataTransformer.zip"
}

resource "aws_s3_bucket_object" "cloudguard_data_transformer" {
  provider = aws.operation
  bucket   = aws_s3_bucket.cloudguard_dashboard_lambda_bucket.id

  key    = "cloudguard-data-transformer-lambda.zip"
  source = data.archive_file.data_transformer_lambda.output_path

  etag = filemd5(data.archive_file.data_transformer_lambda.output_path)
}

# Cloudwatch event rule config
resource "aws_cloudwatch_event_rule" "new_s3_file" {
  provider    = aws.operation
  name        = "CloudGuard-Dashboard-data-transformer"
  description = "Capture new import lambda assets file upload"
  is_enabled  = true


  event_pattern = <<EOF
{
    "source": ["aws.s3"],
    "detail-type": ["AWS API Call via CloudTrail"],
    "detail": {
        "eventSource": ["s3.amazonaws.com"],
        "eventName": ["CopyObject","CompleteMultipartUpload","PutObject"],
        "requestParameters": {
            "bucketName": ["${resource.aws_s3_bucket.cloudguard_dashboard_data_bucket.id}"],
            "key": [{ "prefix": "rawData/" }]
        }
    }
}
EOF
}

resource "aws_lambda_permission" "data_transformer_allow_execution_from_cloudwatch" {
  provider      = aws.operation
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_transformer_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.new_s3_file.arn
}

resource "aws_cloudwatch_event_target" "cloudguard_dashboard_transformer_eventbridge_target" {
  provider  = aws.operation
  target_id = "bugedcoldstart"
  arn       = aws_lambda_function.data_transformer_lambda.arn
  rule      = aws_cloudwatch_event_rule.new_s3_file.name
}

# Role needed to query account in the org. Resides on the master account
resource "aws_iam_role" "query_org_accounts" {
  name     = "CSPM-transformation-Lambda-Query-Org-Accounts"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRole",
        Principal = {
          Service = [
            "organizations.amazonaws.com"
          ]
        }
      },
      {
        Effect = "Allow",
        Action = "sts:AssumeRole",
        Principal = {
          AWS = "${resource.aws_iam_role.data_transformer_lambda_exec_role.arn}"
        }
      }
    ]
  })
}

# Attached AWS managed AWSOrganizationsReadOnlyAccess policy to the Query Org Accounts Role
resource "aws_iam_role_policy_attachment" "query_org_accounts_access" {
  role       = aws_iam_role.query_org_accounts.name
  policy_arn = "arn:aws:iam::aws:policy/AWSOrganizationsReadOnlyAccess"
}

# CloudGuardDataTransformer Lambda role
resource "aws_iam_role" "data_transformer_lambda_exec_role" {
  provider = aws.operation
  name     = "CloudGuardDataTransformerExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Assume role right for the org list account
resource "aws_iam_policy" "cloudguard_dashboard_data_transformer_policies" {
  provider = aws.operation
  name     = "CloudGuardDataTransformerAssumeRole"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow",
        Action   = "sts:AssumeRole",
        Resource = "${resource.aws_iam_role.query_org_accounts.arn}"
      }
    ]
  })
}

# Attach policies
resource "aws_iam_role_policy_attachment" "data_transformer_lambda_assumerole" {
  provider   = aws.operation
  role       = aws_iam_role.data_transformer_lambda_exec_role.name
  policy_arn = aws_iam_policy.cloudguard_dashboard_data_transformer_policies.arn
}

resource "aws_iam_role_policy_attachment" "data_transformer_basic_execution_policy" {
  provider   = aws.operation
  role       = aws_iam_role.data_transformer_lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "data_transformer_parameter_store_readonly_policy" {
  provider   = aws.operation
  role       = aws_iam_role.data_transformer_lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}

# Attach the LambdaPermissions IAM policy to DataTransformer Lambda Execution Role
resource "aws_iam_role_policy_attachment" "data_transformer_lambda_access" {
  provider   = aws.operation
  role       = aws_iam_role.data_transformer_lambda_exec_role.name
  policy_arn = aws_iam_policy.cloudguard_dashboard_lambda_policies.arn
}

resource "aws_lambda_function" "data_transformer_lambda" {
  provider      = aws.operation
  function_name = "CloudGuardDataTransformer"
  description   = "Transforms raw CloudGuard data for consumption by QuickSight"

  s3_bucket = aws_s3_bucket.cloudguard_dashboard_lambda_bucket.id
  s3_key    = aws_s3_bucket_object.cloudguard_data_transformer.key

  runtime                        = "nodejs14.x"
  handler                        = "src/index.index"
  timeout                        = 180
  memory_size                    = 512
  reserved_concurrent_executions = 1 ## This is because of the cold start bug, It allows the double call to "pre-heat the lambda" 

  environment {
    variables = {
      "CLOUDGUARD_DATA_S3_BUCKET_ID" = aws_s3_bucket.cloudguard_dashboard_data_bucket.id
      "ASSUMED_ROLE_ARN"             = resource.aws_iam_role.query_org_accounts.arn
    }
  }

  source_code_hash = data.archive_file.data_transformer_lambda.output_base64sha256
  role             = aws_iam_role.data_transformer_lambda_exec_role.arn
}

##############
# Quicksight #
##############

# Upload quicksight configuration manifest in s3
resource "aws_s3_bucket_object" "manifest_upload" {
  provider = aws.operation
  bucket   = aws_s3_bucket.cloudguard_dashboard_data_bucket.id
  key      = "manifest.json"
  acl      = "private"
  content  = templatefile("${path.module}/resources/manifest.json", { account_id = data.aws_caller_identity.operation.id, region = var.aws_region })
  etag     = filemd5("${path.module}/resources/manifest.json")
}

# Creating the DataSource
resource "aws_quicksight_data_source" "default" {
  provider       = aws.operation
  data_source_id = "CSPM-Dashboard"
  name           = "CSPM Assets list by type and account"
  type           = "S3"

  parameters {
    s3 {
      manifest_file_location {
        bucket = resource.aws_s3_bucket.cloudguard_dashboard_data_bucket.id
        key    = resource.aws_s3_bucket_object.manifest_upload.id
      }
    }
  }

  permission {
    actions = [
      "quicksight:DescribeDataSource",
      "quicksight:DescribeDataSourcePermissions",
      "quicksight:PassDataSource",
    ]
    principal = "arn:aws:quicksight:ca-central-1:${data.aws_caller_identity.operation.id}:user/default/BCGOV_CORE_Quicksight_admin/${var.admin_list[0]}"
  }
}

# Quicksight execution role
resource "aws_iam_role" "quicksight_service_role" {
  provider = aws.operation
  name     = "CloudGuardQuicksightserviceRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRole"
        Principal = {
          Service = "quicksight.amazonaws.com"
        },
      }
    ]
  })
}

# s3 access right for Quicksight
resource "aws_iam_policy" "cloudguard_quicksight_s3_policy" {
  provider = aws.operation
  name     = "CloudGuardQuicksightS3Policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow",
        Action   = "s3:ListAllMyBuckets",
        Resource = "arn:aws:s3:::*"
      },
      {
        Action = [
          "s3:ListBucket"
        ],
        Effect = "Allow",
        Resource = [
          "${resource.aws_s3_bucket.cloudguard_dashboard_data_bucket.arn}"
        ]
      },
      {
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ],
        Effect = "Allow",
        Resource = [
          "${resource.aws_s3_bucket.cloudguard_dashboard_data_bucket.arn}/*"
        ]
      }
    ]
  })
}

#Policy attachment
resource "aws_iam_role_policy_attachment" "Cloudguard_quicksight_default_access_rights" {
  provider   = aws.operation
  role       = aws_iam_role.quicksight_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSQuicksightAthenaAccess"
}

resource "aws_iam_role_policy_attachment" "Cloudguard_quicksight_s3_access_rights" {
  provider   = aws.operation
  role       = aws_iam_role.quicksight_service_role.name
  policy_arn = resource.aws_iam_policy.cloudguard_quicksight_s3_policy.arn
}

################
## SSO Config ##
################

# Quicksight reader access role
resource "aws_iam_role" "quicksight_reader_role" {
  provider             = aws.operation
  name                 = "BCGOV_CORE_Quicksight_reader"
  max_session_duration = 21600

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${data.aws_caller_identity.operation.account_id}:saml-provider/BCGovKeyCloak-${var.kc_realm}"
            },
            "Action": "sts:AssumeRoleWithSAML",
            "Condition": {
                "StringEquals": {
                    "SAML:aud": [
                        "https://signin.aws.amazon.com/saml",
                        "${var.lz_portal_cloudfront_url}"
                    ]
                }
            }
        }
    ]
}
EOF
}

# Quicksight author access role
resource "aws_iam_role" "quicksight_author_role" {
  provider             = aws.operation
  name                 = "BCGOV_CORE_Quicksight_author"
  max_session_duration = 21600

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${data.aws_caller_identity.operation.account_id}:saml-provider/BCGovKeyCloak-${var.kc_realm}"
            },
            "Action": "sts:AssumeRoleWithSAML",
            "Condition": {
                "StringEquals": {
                    "SAML:aud": [
                        "https://signin.aws.amazon.com/saml",
                        "${var.lz_portal_cloudfront_url}"
                    ]
                }
            }
        }
    ]
}
EOF
}

resource "aws_iam_role" "quicksight_admin_role" {
  provider             = aws.operation
  name                 = "BCGOV_CORE_Quicksight_admin"
  max_session_duration = 21600

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${data.aws_caller_identity.operation.account_id}:saml-provider/BCGovKeyCloak-${var.kc_realm}"
            },
            "Action": "sts:AssumeRoleWithSAML",
            "Condition": {
                "StringEquals": {
                    "SAML:aud": [
                        "https://signin.aws.amazon.com/saml",
                        "${var.lz_portal_cloudfront_url}"
                    ]
                }
            }
        }
    ]
}
EOF
}

# Quicksight reader access policy
resource "aws_iam_policy" "quicksight_reader_access_policy" {
  provider = aws.operation
  name     = "QuicksightReaderAccess"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow",
        Resource = "*",
        Action = [
          "quicksight:DescribeDashboard",
          "quicksight:ListAnalyses",
          "quicksight:ListDashboards",
          "quicksight:CreateReader",
          "quicksight:SearchDashboards",
          "quicksight:DescribeUser",
          "quicksight:SearchAnalyses"
        ]
      }
    ]
  })
}

# Quicksight author access policy
resource "aws_iam_policy" "quicksight_author_access_policy" {
  provider = aws.operation
  name     = "QuicksightAuthorAccess"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow",
        Resource = "*",
        Action = [
          "quicksight:DescribeDashboard",
          "quicksight:ListAnalyses",
          "quicksight:ListDashboards",
          "quicksight:CreateUser",
          "quicksight:SearchDashboards",
          "quicksight:DescribeUser",
          "quicksight:SearchAnalyses"
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "quicksight_admin_access_policy" {
  provider = aws.operation
  name     = "QuicksightAdminAccess"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow",
        Resource = "*",
        Action   = "quicksight:*"
      }
    ]
  })
}

# Quicksight access Policies attachment
resource "aws_iam_role_policy_attachment" "quicksight_reader_access" {
  provider   = aws.operation
  role       = aws_iam_role.quicksight_reader_role.name
  policy_arn = aws_iam_policy.quicksight_reader_access_policy.arn
}

resource "aws_iam_role_policy_attachment" "quicksight_author_access" {
  provider   = aws.operation
  role       = aws_iam_role.quicksight_author_role.name
  policy_arn = aws_iam_policy.quicksight_author_access_policy.arn
}

resource "aws_iam_role_policy_attachment" "quicksight_admin_access" {
  provider   = aws.operation
  role       = aws_iam_role.quicksight_admin_role.name
  policy_arn = aws_iam_policy.quicksight_admin_access_policy.arn
}

# Quicksight users creation

resource "aws_quicksight_user" "readers" {
  provider      = aws.operation
  for_each      = toset(var.reader_list)
  session_name  = each.key
  email         = data.keycloak_user.this[each.key].email
  namespace     = "default"
  identity_type = "IAM"
  iam_arn       = aws_iam_role.quicksight_reader_role.arn
  user_role     = "READER"
}

resource "aws_quicksight_user" "authors" {
  provider      = aws.operation
  for_each      = toset(var.author_list)
  session_name  = each.key
  email         = data.keycloak_user.this[each.key].email
  namespace     = "default"
  identity_type = "IAM"
  iam_arn       = aws_iam_role.quicksight_author_role.arn
  user_role     = "AUTHOR"
}

resource "aws_quicksight_user" "admins" {
  provider      = aws.operation
  for_each      = toset(var.admin_list)
  session_name  = each.key
  email         = data.keycloak_user.this[each.key].email
  namespace     = "default"
  identity_type = "IAM"
  iam_arn       = aws_iam_role.quicksight_admin_role.arn
  user_role     = "ADMIN"
}

# Quicksight groups creation
resource "aws_quicksight_group" "reader" {
  provider    = aws.operation
  group_name  = "readers"
  description = "This group for the reader is not really used because user can directly access the public CSPM Dashboard"
}

resource "aws_quicksight_group" "author" {
  provider    = aws.operation
  group_name  = "authors"
  description = "Group link with the CSPM Dashboard; need to be linked on the first execution"
}

resource "aws_quicksight_group" "admin" {
  provider    = aws.operation
  group_name  = "admins"
  description = "Group link with the CSPM Dashboard; need to be linked on the first execution"
}

# Quicksight user group maping

resource "aws_quicksight_group_membership" "readers" {
  provider    = aws.operation
  for_each    = toset(var.reader_list)
  group_name  = "readers"
  member_name = "${aws_iam_role.quicksight_reader_role.name}/${each.key}"

  depends_on = [
    aws_quicksight_user.readers,
    aws_quicksight_group.reader
  ]
}

resource "aws_quicksight_group_membership" "authors" {
  provider    = aws.operation
  for_each    = toset(var.author_list)
  group_name  = "authors"
  member_name = "${aws_iam_role.quicksight_author_role.name}/${each.key}"

  depends_on = [
    aws_quicksight_user.authors,
    aws_quicksight_group.author
  ]
}

resource "aws_quicksight_group_membership" "admins" {
  provider    = aws.operation
  for_each    = toset(var.admin_list)
  group_name  = "admins"
  member_name = "${aws_iam_role.quicksight_admin_role.name}/${each.key}"

  depends_on = [
    aws_quicksight_user.admins,
    aws_quicksight_group.admin
  ]
}
