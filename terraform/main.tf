terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.48.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2.0"
    }
  }

  required_version = "~> 1.0"
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# SSM Parameter Store
resource "aws_ssm_parameter" "cloudguard_api_keys" {
  name  = "/cloudguard_dashboard/cloudguard_api_keys"
  type  = "SecureString"
  value = var.cloudguard_api_keys_parameter
}

# S3 Bucket for Lambda asset
resource "aws_s3_bucket" "cloudguard_dashboard_lambda_bucket" {
  bucket        = "cloudguard-dashboard-lambda-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  acl           = "private"
  force_destroy = false
}

# S3 Bucket for Lambda asset
resource "aws_s3_bucket" "cloudguard_dashboard_data_bucket" {
  bucket        = "cloudguard-dashboard-data-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  acl           = "private"
  force_destroy = false
}

# Install Lambda function dependencies
# Using Terraform to install dependencies. Once a CI/CD mechanism is developed,
# this step could be moved out of Terraform in to the CI/CD flow
resource "null_resource" "install_lambda_dependencies" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = <<-EOF
      cd ${path.module}/../lambda/src &&\
      npm install
    EOF
  }
}

data "archive_file" "cloudguard_dashboard_lambda" {
  type = "zip"

  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/../lambda.zip"
}

resource "aws_s3_bucket_object" "cloudguard_dashboard" {
  bucket = aws_s3_bucket.cloudguard_dashboard_lambda_bucket.id

  key    = "cloudguard-dashboard-lambda.zip"
  source = data.archive_file.cloudguard_dashboard_lambda.output_path

  etag = filemd5(data.archive_file.cloudguard_dashboard_lambda.output_path)
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "CloudGuard-Dashboard-ExecutionRole"

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

resource "aws_iam_role_policy_attachment" "lambda_basic_execution_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_parameter_store_readonly_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}

resource "aws_lambda_permission" "allow_execution_from_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cloudguard_dashboard.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cloudguard_dashboard_eventbridge.arn
}

resource "aws_lambda_function" "cloudguard_dashboard" {
  function_name = "CloudGuard-Dashboard"
  description   = "Pull data from CheckPoint CloudGuard for presenting on a dashboard"

  s3_bucket = aws_s3_bucket.cloudguard_dashboard_lambda_bucket.id
  s3_key    = aws_s3_bucket_object.cloudguard_dashboard.key

  runtime     = "nodejs14.x"
  handler     = "src/index.index"
  timeout     = 180
  memory_size = 512

  environment {
    variables = {
      "CLOUDGUARD_API_ENDPOINT"             = var.cloudguard_api_endpoint
      "CLOUDGUARD_API_KEYS_PARAMETER_STORE" = aws_ssm_parameter.cloudguard_api_keys.name
      "CLOUDGUARD_PAGE_SIZE"                = var.cloudguard_api_page_size
      "CLOUDGUARD_DATA_S3_BUCKET_ID"        = aws_s3_bucket.cloudguard_dashboard_data_bucket.id
    }
  }

  source_code_hash = data.archive_file.cloudguard_dashboard_lambda.output_base64sha256
  role             = aws_iam_role.lambda_exec_role.arn
}

resource "aws_iam_policy" "cloudguard_dashboard_lambda_policies" {
  name = "CloudGuardDashboardLambdaPermissions"
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
      }
    ]
  })
}

# Attach the CloudGuardDashboardLambdaPermissions IAM policy to CloudGuard-Dashboard Lambda Execution Role
resource "aws_iam_role_policy_attachment" "athena_cost_and_usage_report_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.cloudguard_dashboard_lambda_policies.arn
}

resource "aws_cloudwatch_event_rule" "cloudguard_dashboard_eventbridge" {
  name                = "CloudGuard-Dashboard"
  description         = "Query CloudGuard API. Used to trigger the CloudGuard-Dashboard Lambda"
  schedule_expression = "cron(0 19 * * ? *)"
  is_enabled          = false
}

resource "aws_cloudwatch_event_target" "cloudguard_dashboard_eventbridge_target" {
  arn  = aws_lambda_function.cloudguard_dashboard.arn
  rule = aws_cloudwatch_event_rule.cloudguard_dashboard_eventbridge.name
}