from datetime import datetime
import os
import json
import boto3
import logging
import numpy as np # <--- ADDED THIS LINE
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
textract_client = boto3.client('textract')
dynamodb_client = boto3.client('dynamodb')
sagemaker_runtime_client = boto3.client('sagemaker-runtime')
s3_client = boto3.client('s3')

# Environment variables (will be set in Terraform)
SAGEMAKER_ENDPOINT_NAME = os.environ.get('SAGEMAKER_ENDPOINT_NAME')
DYNAMODB_TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME') # Placeholder for future
OPENSEARCH_DOMAIN_ENDPOINT = os.environ.get('OPENSEARCH_DOMAIN_ENDPOINT') # Placeholder for future

opensearch_client = None

def get_awsauth(region, service):
    """
    Returns an AWS4Auth object for signing requests to AWS services.
    """
    credentials = boto3.Session().get_credentials()
    logger.info(f"Retrieved AWS credentials: {credentials}")
    return AWS4Auth(credentials.access_key,
                    credentials.secret_key,
                    region,
                    service,
                    session_token=credentials.token)

def lambda_handler(event, context):
    """
    Lambda handler for processing Textract job completion notifications.
    It retrieves Textract results, sends text for embeddings, and
    (in future steps) stores metadata and indexes into OpenSearch.
    """
    print("Processor Lambda invoked!")
    logger.info(f"Received event: {json.dumps(event)}")
    print(f"Received event: {json.dumps(event)}")
    
    # Process each record from the SQS event
    for record in event['Records']:
        try:
            # SQS message body contains the SNS notification
            message_body = json.loads(record['body'])
            sns_message = json.loads(message_body['Message']) # This is the actual payload


            job_status = sns_message['Status']
            job_id = sns_message['JobId']
            document_location = sns_message['DocumentLocation']
            s3_bucket = document_location['S3Bucket']
            s3_object_key = document_location['S3ObjectName']

            logger.info(f"Processing Textract JobId: {job_id} for document: s3://{s3_bucket}/{s3_object_key}")

            if job_status == 'SUCCEEDED':
                # --- 1. Retrieve Textract Analysis Results ---
                full_text = ""
                try:
                    # Get the initial results
                    response = textract_client.get_document_analysis(JobId=job_id)
                    blocks = response['Blocks']
                    
                    # Extract text from blocks (simplified for now)
                    for block in blocks:
                        if block['BlockType'] == 'LINE':
                            full_text += block['Text'] + "\n"

                    # Handle pagination for large documents
                    while 'NextToken' in response:
                        next_token = response['NextToken']
                        response = textract_client.get_document_analysis(JobId=job_id, NextToken=next_token)
                        for block in response['Blocks']:
                            if block['BlockType'] == 'LINE':
                                full_text += block['Text'] + "\n"
                    
                    logger.info(f"Extracted {len(full_text)} characters from Textract job.")

                except Exception as e:
                    logger.error(f"Error retrieving or parsing Textract results for JobId {job_id}: {e}")
                    # In a real scenario, you might update DynamoDB with a FAILED status
                    continue # Move to next SQS record

                # --- 2. Generate Semantic Embeddings (Call SageMaker Endpoint) ---
                if not SAGEMAKER_ENDPOINT_NAME:
                    logger.error("SAGEMAKER_ENDPOINT_NAME environment variable not set. Cannot generate embeddings.")
                    continue

                # IMPORTANT: For large documents, you MUST chunk the 'full_text'
                # and send chunks to SageMaker, then combine/average embeddings.
                # This example sends the full text, which will fail if too long.
                # We will implement proper chunking later.
                try:
                    # Prepare payload for SageMaker endpoint
                    logger.info("Invoking SageMaker endpoint...")
                    logger.info(f"Payload size: {len(full_text)} characters.")
                    sagemaker_payload = {"text": full_text[:500]} # Send only first 500 chars for initial testing
                    
                    # Invoke SageMaker endpoint
                    sagemaker_response = sagemaker_runtime_client.invoke_endpoint(
                        EndpointName=SAGEMAKER_ENDPOINT_NAME,
                        ContentType='application/json',
                        Body=json.dumps(sagemaker_payload)
                    )
                    
                    # Parse SageMaker response
                    response_body = sagemaker_response['Body'].read().decode('utf-8')
                    embeddings = json.loads(response_body)['embeddings']
                    logger.info(f"Successfully generated embeddings (shape: {np.array(embeddings).shape}).")

                    # You would typically store these embeddings, perhaps averaged for the document,
                    # or individual chunk embeddings, in OpenSearch.

                except Exception as e:
                    logger.error(f"Error invoking SageMaker endpoint {SAGEMAKER_ENDPOINT_NAME} for JobId {job_id}: {e}")
                    # Update status in DynamoDB, move to DLQ etc.
                    continue

               
                
                dynamodb_client.put_item(
                    TableName=DYNAMODB_TABLE_NAME,
                    Item={
                        'document_id': {'S': job_id},
                        's3_path': {'S': f"s3://{s3_bucket}/{s3_object_key}"},
                        'status': {'S': 'EMBEDDINGS_GENERATED'},
                        'timestamp': {'S': datetime.now().isoformat()}
                    }
                )
                logger.info("DynamoDB storage placeholder executed.")
                logger.info("Initializing OpenSearch client...")
                opensearch_client = OpenSearch(
                    hosts = [{'host': OPENSEARCH_DOMAIN_ENDPOINT, 'port': 443}],
                    http_auth = get_awsauth('us-east-1', 'es'), # Needs proper AWS SigV4 auth
                    use_ssl = True,
                    verify_certs = True,
                    connection_class = RequestsHttpConnection
                )
                logger.info("OpenSearch client initialized.")
                logger.info("Indexing into OpenSearch...")
                response = opensearch_client.index(
                    index='index',  # or your custom index name
                    id=job_id,
                    body={
                        "document_id": job_id,
                        "text_content": full_text,
                        "embedding": embeddings[0],
                        "timestamp": datetime.now()
                    }
                )
                logger.info("OpenSearch indexing placeholder executed.")

                logger.info(f"Successfully processed Textract JobId: {job_id}")

            elif job_status == 'FAILED':
                logger.error(f"Textract job {job_id} failed. Reason: {sns_message.get('FailureReason', 'N/A')}")
                # Update DynamoDB with FAILED status
            else:
                logger.warning(f"Textract job {job_id} has unexpected status: {job_status}")

        except json.JSONDecodeError as e:
            logger.error(f"Error decoding JSON from SQS message: {e}. Message body: {record['body']}")
        except KeyError as e:
            logger.error(f"Missing expected key in SQS/SNS message: {e}. Message body: {record['body']}")
        except Exception as e:
            logger.error(f"An unexpected error occurred while processing SQS record: {e}", exc_info=True)

    return {
        'statusCode': 200,
        'body': json.dumps('Processor Lambda execution complete')
    }