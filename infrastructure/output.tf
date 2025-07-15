output "sagemaker_embeddings_endpoint_name" {
  description = "The name of the SageMaker Serverless Inference Endpoint for embeddings."
  value       = aws_sagemaker_endpoint.embeddings-endpoint.name
}
