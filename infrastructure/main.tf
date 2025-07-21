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

data "aws_caller_identity" "current" {}

resource "aws_sns_topic_policy" "textract_sns_topic_policy" {
  arn = aws_sns_topic.textract-notification-topic.arn

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowSNSPublish",
        Effect = "Allow",
        Principal = {
          Service = "sns.amazonaws.com" # Allow SNS service to publish
        },
        Action   = "sns:Publish",
        Resource = aws_sns_topic.textract-notification-topic.arn,
        Condition = {
          StringEquals = {
            "aws:SourceOwner" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowTextractPublish",
        Effect = "Allow",
        Principal = {
          Service = "textract.amazonaws.com" # Explicitly allow Textract to publish
        },
        Action   = "sns:Publish",
        Resource = aws_sns_topic.textract-notification-topic.arn,
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
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
        Effect   = "Allow",
        Action   = ["sns:Publish"],
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
      TEXTRACT_OUTPUT_S3_BUCKET   = aws_s3_bucket.textract-output-bucket.bucket
      TEXTRACT_SNS_TOPIC_ARN      = aws_sns_topic.textract-notification-topic.arn
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
        Action   = "s3:GetObject"
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
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.textract-output-bucket.arn}/*"
      }
    ]
  })
}

resource "aws_sqs_queue" "lambda_dlq" {
  name = "lambda-dead-letter-queue"
}
resource "aws_sqs_queue" "textract-notification-queue" {
  name                       = "DocuInsight-Textract-Notification-Queue"
  visibility_timeout_seconds = 200

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.lambda_dlq.arn
    maxReceiveCount     = 2
  })
  tags = {
    Name = "DocuInsight-Textract-Notification-Queue"
  }
}

resource "aws_sns_topic_subscription" "textract-notification-subscription" {
  topic_arn = aws_sns_topic.textract-notification-topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.textract-notification-queue.arn
}

resource "aws_sns_topic_subscription" "email-notification-subscription" {
  topic_arn = aws_sns_topic.textract-notification-topic.arn
  protocol  = "email"
  endpoint  = "mehabawyohanse@gmail.com"
}


resource "aws_sqs_queue_policy" "textract-notification-queue-policy" {
  queue_url = aws_sqs_queue.textract-notification-queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.textract-notification-queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.textract-notification-topic.arn
          }
        }
      }
    ]
  })
}

resource "aws_ecr_repository" "sagemaker-embeddings-repo" {
  name                 = "docuinsight-sagemaker-model-repo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  tags = {
    Name = "DocuInsight-SageMaker-Model-Repo"
  }
}
resource "aws_iam_role" "sagemaker-execution-role" {
  name = "docuinsight-sagemaker-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "sagemaker.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "docuinsight-sagemaker-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "sagemaker-ecr-policy" {
  role       = aws_iam_role.sagemaker-execution-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly" # Allows pulling from ECR
}

resource "aws_iam_role_policy_attachment" "sagemaker-cloudwatch-logs_policy" {
  role       = aws_iam_role.sagemaker-execution-role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess" # For logging (can be more restrictive)
}


resource "aws_sagemaker_model" "embeddings-model" {
  name               = "docuinsight-embeddings-model"
  execution_role_arn = aws_iam_role.sagemaker-execution-role.arn

  primary_container {
    image = "${aws_ecr_repository.sagemaker-embeddings-repo.repository_url}:latest"

  }

  tags = {
    Name = "docuinsight-embeddings-model"
  }
}

resource "aws_sagemaker_endpoint_configuration" "embeddings-endpoint-config" {
  name = "docuinsight-embeddings-endpoint-config"

  production_variants {
    variant_name = "default"
    model_name   = aws_sagemaker_model.embeddings-model.name

    # Crucial for Serverless Inference:
    serverless_config {
      memory_size_in_mb = 2048
      max_concurrency   = 1
    }
  }

  tags = {
    Name = "docuinsight-embeddings-endpoint-config"
  }
}

resource "aws_sagemaker_endpoint" "embeddings-endpoint" {
  name                 = "docuinsight-embeddings-endpoint-v2"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.embeddings-endpoint-config.name

  tags = {
    Name = "docuinsight-embeddings-endpoint"
  }
}

# --- IAM Role for Processor Lambda ---
resource "aws_iam_role" "processor-lambda-role" {
  name = "docuinsight-processor-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "docuinsight-processor-lambda-role"
  }
}

resource "aws_iam_role_policy" "processor-lambda-policy" {
  name = "docuinsight-processor-lambda-policy"
  role = aws_iam_role.processor-lambda-role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ],
        Effect   = "Allow",
        Resource = aws_sqs_queue.textract-notification-queue.arn
      },
      {
        Action = [
          "textract:GetDocumentAnalysis"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "s3:GetObject"
        ],
        Effect   = "Allow",
        Resource = "${aws_s3_bucket.textract-output-bucket.arn}/*" # Allow reading from Textract output bucket
      },
      {
        Action = [
          "sagemaker:InvokeEndpoint"
        ],
        Effect   = "Allow",
        Resource = aws_sagemaker_endpoint.embeddings-endpoint.arn # Allow invoking your SageMaker endpoint
      },
      # Placeholder for DynamoDB permissions (will enable later)
      # {
      #   Action = [
      #     "dynamodb:PutItem",
      #     "dynamodb:UpdateItem",
      #     "dynamodb:GetItem"
      #   ],
      #   Effect   = "Allow",
      #   Resource = aws_dynamodb_table.document_metadata.arn
      # },
      # Placeholder for OpenSearch permissions (will enable later)
      {
        Effect = "Allow",
        Action = [
          "es:*"
        ],
        Resource = [
          aws_opensearch_domain.document-search-domain.arn,       # Correct resource block name and .arn
          "${aws_opensearch_domain.document-search-domain.arn}/*" # For collection and index access
        ]
      }
    ]
  })
}

resource "aws_lambda_layer_version" "numpy-layer" {
  filename            = "../src/numpy-layer/lambda-layer.zip"
  layer_name          = "numpy"
  compatible_runtimes = ["python3.12"]

  source_code_hash = filebase64sha256("../src/numpy-layer/lambda-layer.zip")
}
resource "aws_lambda_function" "processor-lambda" {
  function_name = "docuinsight-processor-lambda"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  role          = aws_iam_role.processor-lambda-role.arn
  timeout       = 180  # Increased timeout for potential cold starts and processing
  memory_size   = 1024 # Start with 1GB memory
  # Reference the manually created zip file
  filename         = "../src/processor_lambda/lambda_function.zip"
  source_code_hash = filebase64sha256("../src/processor_lambda/lambda_function.zip")
  layers = [
    aws_lambda_layer_version.numpy-layer.arn, # Include the numpy layer
  ]

  environment {
    variables = {
      SAGEMAKER_ENDPOINT_NAME = aws_sagemaker_endpoint.embeddings-endpoint.name
      # DYNAMODB_TABLE_NAME     = aws_dynamodb_table.document_metadata.name # Placeholder
      OPENSEARCH_DOMAIN_ENDPOINT = replace(aws_opensearch_domain.document-search-domain.endpoint, "https://", "")
      LOG_LEVEL                  = "INFO"
    }
  }

  tags = {
    Name = "docuinsight-processor-lambda"
  }
}
resource "aws_lambda_event_source_mapping" "processor-lambda-sqs-trigger" {
  event_source_arn = aws_sqs_queue.textract-notification-queue.arn
  function_name    = aws_lambda_function.processor-lambda.arn
  batch_size       = 1 # Process one SQS message at a time for now
  enabled          = true
  depends_on = [
    aws_lambda_function.processor-lambda,
    aws_sqs_queue.textract-notification-queue,
    aws_lambda_permission.allow-sqs-to-invoke-processor-lambda
  ]

}

resource "aws_lambda_permission" "allow-sqs-to-invoke-processor-lambda" {
  statement_id  = "AllowExecutionFromSQS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor-lambda.function_name
  principal     = "sqs.amazonaws.com"
  source_arn    = aws_sqs_queue.textract-notification-queue.arn
}

# --- New CloudWatch Log Groups for OpenSearch Logs ---
resource "aws_cloudwatch_log_group" "opensearch_index_slow_logs" {
  name              = "/aws/opensearch/domains/docuinsight-search-domain/index-slow-logs"
  retention_in_days = 14 # Adjust retention as needed
  tags = {
    Name = "DocuInsight-OpenSearch-Index-Slow-Logs"
  }
}

resource "aws_cloudwatch_log_group" "opensearch_search_slow_logs" {
  name              = "/aws/opensearch/domains/docuinsight-search-domain/search-slow-logs"
  retention_in_days = 14 # Adjust retention as needed
  tags = {
    Name = "DocuInsight-OpenSearch-Search-Slow-Logs"
  }
}

resource "aws_cloudwatch_log_group" "opensearch_audit_logs" {
  name              = "/aws/opensearch/domains/docuinsight-search-domain/audit-logs"
  retention_in_days = 14 # Adjust retention as needed
  tags = {
    Name = "DocuInsight-OpenSearch-Audit-Logs"
  }
}

resource "aws_opensearch_domain" "document-search-domain" {
  domain_name           = "docuinsight-search-domain" # Must be unique
  engine_version        = "OpenSearch_2.11" # Choose a recent, stable version

  cluster_config {
    instance_type = "t3.small.search" # Free Tier eligible instance type
    instance_count = 1                # For Free Tier, keep at 1
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp2" # gp2 is fine for Free Tier
    volume_size = 10    # 10 GB is Free Tier limit
  }

  
  domain_endpoint_options {
    enforce_https = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }
  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_index_slow_logs.arn
    log_type                 = "INDEX_SLOW_LOGS"
    enabled                  = true
  }
  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_search_slow_logs.arn
    log_type                 = "SEARCH_SLOW_LOGS"
    enabled                  = true
  }
  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_audit_logs.arn
    log_type                 = "AUDIT_LOGS"
    enabled                  = true
  }

  tags = {
    Name = "DocuInsight-Traditional-OpenSearch-Domain"
  }
}

resource "aws_opensearch_domain_policy" "document-search-policy" {
  domain_name = aws_opensearch_domain.document-search-domain.domain_name

  access_policies = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          AWS = aws_iam_role.processor-lambda-role.arn # Allow Processor Lambda role
        },
        Action = "es:*", # Grant all OpenSearch actions for now (can be refined)
        Resource = [
          aws_opensearch_domain.document-search-domain.arn,
          "${aws_opensearch_domain.document-search-domain.arn}/*" # For index-level permissions
        ]
      }
    ]
  })
}