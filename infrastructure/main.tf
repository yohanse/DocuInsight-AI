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