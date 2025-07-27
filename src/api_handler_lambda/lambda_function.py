import os
import json
import boto3
import logging
import base64
import uuid
import re
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth
import numpy as np
from requests_toolbelt.multipart import decoder

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# AWS clients
s3_client = boto3.client('s3')
sagemaker_runtime_client = boto3.client('sagemaker-runtime')

# Environment variables
SAGEMAKER_ENDPOINT_NAME = os.environ.get('SAGEMAKER_ENDPOINT_NAME')
OPENSEARCH_DOMAIN_ENDPOINT = os.environ.get('OPENSEARCH_DOMAIN_ENDPOINT')
AWS_REGION = os.environ.get('AWS_REGION')
OPENSEARCH_INDEX_NAME = "index"
S3_INPUT_BUCKET = os.environ.get('S3_INPUT_BUCKET')

# Global OpenSearch client
opensearch_client = None

def get_awsauth(region, service):
    credentials = boto3.Session().get_credentials()
    return AWS4Auth(credentials.access_key,
                    credentials.secret_key,
                    region,
                    service,
                    session_token=credentials.token)

def initialize_opensearch_client():
    global opensearch_client
    if opensearch_client is None:
        if not OPENSEARCH_DOMAIN_ENDPOINT or not AWS_REGION:
            logger.error("Missing OpenSearch config.")
            return False
        try:
            opensearch_client = OpenSearch(
                hosts=[{'host': OPENSEARCH_DOMAIN_ENDPOINT, 'port': 443}],
                http_auth=get_awsauth(AWS_REGION, 'es'),
                use_ssl=True,
                verify_certs=True,
                connection_class=RequestsHttpConnection,
                timeout=30
            )
            logger.info("OpenSearch client initialized.")
            return True
        except Exception as e:
            logger.error(f"Failed to init OpenSearch: {e}", exc_info=True)
            return False
    return True

def sanitize_filename(name):
    return re.sub(r'[^a-zA-Z0-9_.-]', '_', name)

def handle_upload(event):
    logger.info("Handling upload request")
    body = json.loads(event['body'])
    file_name = body['fileName']
    file_type = body['fileType']

    # Optional: Add timestamp prefix or UUID
    key = f"{uuid.uuid4()}_{file_name}"

    url = s3_client.generate_presigned_url(
        'put_object',
        Params={
            'Bucket': S3_INPUT_BUCKET,
            'Key': key,
            'ContentType': file_type
        },
        ExpiresIn=300  # URL valid for 5 mins
    )

    return {
        "statusCode": 200,
        "headers": { "Content-Type": "application/json" },
        "body": json.dumps({
            "uploadUrl": url,
            "fileKey": key
        })
    }


def handle_search(event):
    logger.info("Handling search request")
    if not initialize_opensearch_client():
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'message': 'OpenSearch not ready'})
        }

    try:
        body = json.loads(event['body'])
        user_query = body.get('query_text')
        if not user_query:
            return {'statusCode': 400, 'body': json.dumps({'message': 'Missing query_text'})}
    except Exception as e:
        logger.error(f"Failed to parse search body: {e}")
        return {'statusCode': 400, 'body': json.dumps({'message': 'Invalid JSON'})}

    try:
        sagemaker_response = sagemaker_runtime_client.invoke_endpoint(
            EndpointName=SAGEMAKER_ENDPOINT_NAME,
            ContentType='application/json',
            Body=json.dumps({"text": user_query})
        )
        response_body = sagemaker_response['Body'].read().decode('utf-8')
        embedding = json.loads(response_body)['embeddings']
        if not embedding or not isinstance(embedding[0], list):
            raise ValueError("Invalid embedding format")
        embedding = embedding[0]
    except Exception as e:
        logger.error(f"SageMaker error: {e}")
        return {'statusCode': 500, 'body': json.dumps({'message': f'Embedding generation failed: {str(e)}'})}

    try:
        search_body = {
            "size": 5,
            "query": {
                "knn": {
                    "embedding": {
                        "vector": embedding,
                        "k": 5
                    }
                }
            },
            "_source": ["document_id", "text_content", "timestamp"]
        }

        response = opensearch_client.search(index=OPENSEARCH_INDEX_NAME, body=search_body)
        results = []
        for hit in response['hits']['hits']:
            results.append({
                "score": hit['_score'],
                "job_id": hit['_id'],
                "document_id": hit['_source'].get('document_id'),
                "full_text_preview": hit['_source'].get('text_content', '')[:500],
                "timestamp": hit['_source'].get('timestamp')
            })

        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'query_text': user_query, 'results': results})
        }

    except Exception as e:
        logger.error(f"Search error: {e}", exc_info=True)
        return {'statusCode': 500, 'body': json.dumps({'message': f'Search failed: {str(e)}'})}

def lambda_handler(event, context):
    logger.info(f"Event: {json.dumps(event)}")
    path = event.get('path')
    method = event.get('httpMethod')
    if path == '/upload/' and method == 'POST':
        return handle_upload(event)
    elif path == '/search/' and method == 'POST':
        return handle_search(event)
    else:
        return {
            'statusCode': 404,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'message': 'Route not found'})
        }
