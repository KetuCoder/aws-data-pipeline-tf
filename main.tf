terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

# -----------------------------------
# S3 Buckets
# -----------------------------------
resource "aws_s3_bucket" "data_ingestion" {
  bucket = "employee-data-ingestion-bucket"
}

resource "aws_s3_bucket" "summary_reports" {
  bucket = "employee-summary-reports-bucket"
}

# -----------------------------------
# DynamoDB Table
# -----------------------------------
resource "aws_dynamodb_table" "employees" {
  name           = "Employees"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "employee_id"

  attribute {
    name = "employee_id"
    type = "S"
  }
}

# -----------------------------------
# SNS Topic + Email Subscription
# -----------------------------------
resource "aws_sns_topic" "daily_report_notifications" {
  name = "DailySummaryNotifications"
}

# ✅ Email endpoint for report notifications
resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.daily_report_notifications.arn
  protocol  = "email"
  endpoint  = "ambureketan@gmail.com" # 🔁 Replace with your email
}

# -----------------------------------
# IAM Role and Policy for Lambda
# -----------------------------------
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "lambda_data_pipeline_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda_data_pipeline_policy"
  description = "Permissions for Lambda to access S3, DynamoDB, SNS, and CloudWatch Logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # DynamoDB permissions
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:Scan",
          "dynamodb:DescribeTable"
        ]
        Resource = aws_dynamodb_table.employees.arn
      },

      # S3 permissions
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.data_ingestion.arn,
          "${aws_s3_bucket.data_ingestion.arn}/*",
          aws_s3_bucket.summary_reports.arn,
          "${aws_s3_bucket.summary_reports.arn}/*"
        ]
      },

      # SNS permissions
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.daily_report_notifications.arn
      },

      # CloudWatch Logs
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_role_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# -----------------------------------
# Lambda: ProcessEmployeeCSV
# -----------------------------------
resource "aws_lambda_function" "process_csv" {
  function_name = "ProcessEmployeeCSV"
  role          = aws_iam_role.lambda_role.arn
  handler       = "process_csv.lambda_handler"
  runtime       = "python3.12"

  filename         = "${path.module}/lambda/process_csv.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/process_csv.zip")
}

# -----------------------------------
# Lambda: DailyEmployeeSummary
# -----------------------------------
resource "aws_lambda_function" "daily_summary" {
  function_name = "DailyEmployeeSummary"
  role          = aws_iam_role.lambda_role.arn
  handler       = "daily_summary.lambda_handler"
  runtime       = "python3.12"

  environment {
    variables = {
      REPORT_BUCKET = aws_s3_bucket.summary_reports.bucket
      SNS_TOPIC_ARN = aws_sns_topic.daily_report_notifications.arn
    }
  }

  filename         = "${path.module}/lambda/daily_summary.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/daily_summary.zip")
}

# -----------------------------------
# S3 → Lambda Trigger
# -----------------------------------
resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowS3InvokeProcessCSV"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_csv.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.data_ingestion.arn
}

resource "aws_s3_bucket_notification" "s3_trigger" {
  bucket = aws_s3_bucket.data_ingestion.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.process_csv.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}

# -----------------------------------
# EventBridge Daily Trigger
# -----------------------------------
resource "aws_cloudwatch_event_rule" "daily_trigger" {
  name                = "DailyEmployeeSummaryRule"
  schedule_expression = "cron(0 0 * * ? *)" # Every day at midnight UTC
}

resource "aws_cloudwatch_event_target" "daily_target" {
  rule      = aws_cloudwatch_event_rule.daily_trigger.name
  target_id = "DailySummaryLambda"
  arn       = aws_lambda_function.daily_summary.arn
}

resource "aws_lambda_permission" "allow_event_invoke" {
  statement_id  = "AllowEventInvokeSummaryLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.daily_summary.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_trigger.arn
}
