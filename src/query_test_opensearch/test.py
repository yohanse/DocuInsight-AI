from opensearchpy import OpenSearch
from datetime import datetime
import boto3
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth

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

index_name = 'index'  # Replace with your actual index name

# Initialize the client (you may already have this in your code)
opensearch_client = OpenSearch(
    hosts=[{'host': "search-docuinsight-search-domain-x4n6dwfufcd57gpkxq25dp6qza.us-east-1.es.amazonaws.com", 'port': 443}],
    http_auth=get_awsauth('us-east-1', 'es'),
    use_ssl=True,
    verify_certs=True,
    connection_class=RequestsHttpConnection
)

index_mapping = {
    "settings": {
        "index": {
            "knn": True 
        }
    },
    "mappings": {
        "properties": {
            "document_id": {"type": "keyword"},
            "text_content": {"type": "text"},
            "embedding": {
                "type": "knn_vector",
                "dimension": 384
            },
            "timestamp": {"type": "date"}
        }
    }
}

# Create the new index
response = opensearch_client.indices.create(
    index=index_name,
    body=index_mapping
)

print("Index recreated:", response)

