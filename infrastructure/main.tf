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