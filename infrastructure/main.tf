terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.0.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "document-input-bucket" {
  bucket        = "docuinsight-input-bucket"
  force_destroy = true
  tags = {
    Name = "DocuInsight-Input-Bucket"
  }
}

resource "aws_s3_bucket" "textract-output-bucket" {
  bucket        = "docuinsight-textract-output-bucket"
  force_destroy = true
  tags = {
    Name = "DocuInsight-Textract-Output-Bucket"
  }
}

resource "aws_s3_bucket_cors_configuration" "textract-output-bucket-cors" {
  bucket = aws_s3_bucket.textract-output-bucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = []
    max_age_seconds = 3000
  }
}

resource "aws_dynamodb_table" "document-metadata-table" {
  name         = "DocuInsight-Document-Metadata"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "document_id"

  attribute {
    name = "document_id"
    type = "S"
  }

  tags = {
    Name = "DocuInsight-Document-Metadata"
  }
}

resource "aws_sns_topic" "textract-notification-topic" {
  name = "DocuInsight-Textract-Notification-Topic"
  tags = {
    Name = "DocuInsight-Textract-Notification-Topic"
  }
}

resource "aws_cloudwatch_log_group" "orchestrator-lambda-log-group" {
  name              = "/aws/lambda/DocuInsight-Orchestrator-Lambda"
  retention_in_days = 14
}

resource "aws_iam_role" "orchestrator-lambda-role" {
  name = "DocuInsight-Orchestrator-Lambda-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "orchestrator-lambda-policy" {
  name = "DocuInsight-Orchestrator-Lambda-Policy"
  role = aws_iam_role.orchestrator-lambda-role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:*"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.document-input-bucket.arn,
          "${aws_s3_bucket.document-input-bucket.arn}/*",

        ]
      },
      {
        Effect = "Allow",
        Action = ["s3:*"],
        Resource = [
          aws_s3_bucket.textract-output-bucket.arn,
          "${aws_s3_bucket.textract-output-bucket.arn}/*",

        ]
      },
      {
        Effect = "Allow"
        Action = [
          "textract:StartDocumentAnalysis",
          "textract:GetDocumentAnalysis",
          "textract:GetDocumentTextDetection",
          "textract:StartDocumentTextDetection"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          aws_cloudwatch_log_group.orchestrator-lambda-log-group.arn,
          "${aws_cloudwatch_log_group.orchestrator-lambda-log-group.arn}:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "textract-service-publish-role" {
  name = "TextractServicePublishRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "textract.amazonaws.com"
      }
    },
    ]
  })
}

resource "aws_iam_role_policy" "textract-service-publish-policy" {
  name = "TextractServicePublishPolicy"
  role = aws_iam_role.textract-service-publish-role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:*"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.document-input-bucket.arn,
          "${aws_s3_bucket.document-input-bucket.arn}/*",

        ]
      },
      {
        Effect = "Allow",
        Action = ["s3:*"],
        Resource = [
          aws_s3_bucket.textract-output-bucket.arn,
          "${aws_s3_bucket.textract-output-bucket.arn}/*",

        ]
      },
      {
        Effect = "Allow",
        Action = ["sns:Publish"],
        Resource = aws_sns_topic.textract-notification-topic.arn
      }
    ]
  })
}

resource "aws_lambda_function" "orchestrator-lambda" {
  function_name = "DocuInsight-Orchestrator-Lambda"
  role          = aws_iam_role.orchestrator-lambda-role.arn
  handler       = "lambda_function.handler"
  runtime       = "python3.12"
  timeout       = 900

  environment {
    variables = {
      TEXTRACT_OUTPUT_S3_BUCKET = aws_s3_bucket.textract-output-bucket.bucket
      TEXTRACT_SNS_TOPIC_ARN    = aws_sns_topic.textract-notification-topic.arn
      TEXTRACT_SNS_TOPIC_ROLE_ARN = aws_iam_role.textract-service-publish-role.arn
    }
  }
  filename         = "../src/orchestrator_lambda/lambda_function.zip"
  source_code_hash = filebase64sha256("../src/orchestrator_lambda/lambda_function.zip")
}

resource "aws_lambda_permission" "allow-s3-to-trigger-orchestrator-lambda" {
  statement_id  = "AllowS3ToInvokeOrchestratorLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orchestrator-lambda.arn
  principal     = "s3.amazonaws.com"

  source_arn = aws_s3_bucket.document-input-bucket.arn
}

resource "aws_s3_bucket_notification" "orchestrator-trigger" {
  bucket = aws_s3_bucket.document-input-bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.orchestrator-lambda.arn
    events              = ["s3:ObjectCreated:*"]
  }
    depends_on = [
    aws_lambda_permission.allow-s3-to-trigger-orchestrator-lambda
  ]
}

resource "aws_s3_bucket_policy" "document-input-bucket-policy" {
  bucket = aws_s3_bucket.document-input-bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "textract.amazonaws.com"
        }
        Action = "s3:GetObject"
        Resource = "${aws_s3_bucket.document-input-bucket.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "textract-output-bucket-policy" {
  bucket = aws_s3_bucket.textract-output-bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "textract.amazonaws.com"
        }
        Action = "s3:PutObject"
        Resource = "${aws_s3_bucket.textract-output-bucket.arn}/*"
      }
    ]
  })
}

resource "aws_sqs_queue" "textract-notification-queue" {
  name = "DocuInsight-Textract-Notification-Queue"
  tags = {
    Name = "DocuInsight-Textract-Notification-Queue"
  }
}

resource "aws_sns_topic_subscription" "textract-notification-subscription" {
  topic_arn = aws_sns_topic.textract-notification-topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.textract-notification-queue.arn

  filter_policy = jsonencode({
    event_type = ["TEXTRACT_JOB_COMPLETED"]
  })
}