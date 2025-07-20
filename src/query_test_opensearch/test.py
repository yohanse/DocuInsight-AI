import os
import json
import boto3
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth

# --- Configuration ---
# Replace with the actual endpoint of your OpenSearch Serverless collection
# Example: "xxxxxxxxxxxxxxxxx.us-east-1.aoss.amazonaws.com"
OPENSEARCH_HOST = "YOUR_OPENSEARCH_COLLECTION_ENDPOINT_HERE"
# Replace with the JobId you copied from the Processor Lambda logs
JOB_ID_TO_SEARCH = "YOUR_JOB_ID_HERE"
# The index name used in your Processor Lambda
INDEX_NAME = "documents"

# AWS Region where your OpenSearch collection is deployed
AWS_REGION = "us-east-1"
# Service name for OpenSearch Serverless authentication
SERVICE = 'aoss'

# --- AWS Authentication Helper (same as in your Lambda) ---
def get_awsauth(region, service):
    """
    Returns an AWS4Auth object for signing requests to AWS services.
    """
    credentials = boto3.Session().get_credentials()
    return AWS4Auth(credentials.access_key,
                    credentials.secret_key,
                    region,
                    service,
                    session_token=credentials.token)

# --- Main Query Logic ---
def query_opensearch():
    # Initialize OpenSearch client
    try:
        auth = get_awsauth(AWS_REGION, SERVICE)
        client = OpenSearch(
            hosts = [{'host': OPENSEARCH_HOST, 'port': 443}],
            http_auth = auth,
            use_ssl = True,
            verify_certs = True,
            connection_class = RequestsHttpConnection,
            timeout = 30
        )
        print(f"Connected to OpenSearch at {OPENSEARCH_HOST}")

    except Exception as e:
        print(f"Error initializing OpenSearch client: {e}")
        return

    # --- 1. Check if the index exists ---
    try:
        if not client.indices.exists(index=INDEX_NAME):
            print(f"Index '{INDEX_NAME}' does not exist. No documents to search.")
            return
        print(f"Index '{INDEX_NAME}' exists.")
    except Exception as e:
        print(f"Error checking if index exists: {e}")
        return

    # --- 2. Search for the specific JobId ---
    # We'll use a match query on the 'job_id' field
    search_body = {
        "query": {
            "match": {
                "job_id": JOB_ID_TO_SEARCH
            }
        }
    }

    print(f"\nSearching for document with JobId: {JOB_ID_TO_SEARCH} in index: {INDEX_NAME}")
    try:
        response = client.search(
            index = INDEX_NAME,
            body = search_body
        )
        
        print("\n--- Search Results ---")
        print(json.dumps(response, indent=2))

        if response['hits']['total']['value'] > 0:
            print(f"\nSUCCESS: Found {response['hits']['total']['value']} document(s) for JobId '{JOB_ID_TO_SEARCH}'.")
            for hit in response['hits']['hits']:
                print(f"  Document ID: {hit['_id']}")
                print(f"  Source (first 200 chars): {hit['_source']['full_text'][:200]}...")
        else:
            print(f"\nFAILURE: No documents found for JobId '{JOB_ID_TO_SEARCH}'.")

    except Exception as e:
        print(f"Error during OpenSearch search: {e}")

if __name__ == "__main__":
    # IMPORTANT: Ensure your AWS credentials are configured in your environment
    # (e.g., via AWS CLI 'aws configure' or environment variables AWS_ACCESS_KEY_ID, etc.)
    # for boto3.Session().get_credentials() to work.
    query_opensearch()
