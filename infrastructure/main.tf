terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "6.0.0"
    }
  }
}

provider "aws" {
    region = "us-east-1"
}


resource "aws_s3_bucket" "document-input-bucket" {
    bucket = "DocuInsight-Input-Bucket"
    force_destroy = true
    tags = {
        Name = "DocuInsight-Input-Bucket"
    }
}


resource "aws_s3_bucket" "textract-output-bucket" {
    bucket = "DocuInsight-Textract-Output-Bucket"
    force_destroy = true
    tags = {
        Name = "DocuInsight-Input-Bucket"
    }
}

resource "aws_dynamodb_table" "document-metadata-table" {
    name           = "DocuInsight-Document-Metadata"
    billing_mode   = "PAY_PER_REQUEST"
    hash_key       = "document_id"

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

resource "aws_sqs_queue" "textract-job-queue-sqs" {
    name                      = "textract-job-queue-sqs"
    delay_seconds             = 90
    max_message_size          = 2048
    message_retention_seconds = 86400
    receive_wait_time_seconds = 10
    

    tags = {
        Environment = "production"
    }
}