import os
import boto3
import json

s3_client = boto3.client('s3')
textract_client = boto3.client("textract", region_name="us-east-1")

TEXTRACT_OUTPUT_S3_BUCKET = os.environ.get('TEXTRACT_OUTPUT_S3_BUCKET')
TEXTRACT_SNS_TOPIC_ARN = os.environ.get('TEXTRACT_SNS_TOPIC_ARN')
TEXTRACT_SNS_TOPIC_ROLE_ARN = os.environ.get('TEXTRACT_SNS_TOPIC_ROLE_ARN')

def handler(event, context):
    """
    Lambda handler for the Orchestrator function.
    Triggered by S3 ObjectCreated events.
    Initiates an asynchronous Textract document analysis job.
    """
    print(f"Received event: {json.dumps(event)}")

    # Extract bucket name and object key from the S3 event
    if 'Records' not in event or not event['Records']:
        print("No records found in the S3 event.")
        return {
            'statusCode': 400,
            'body': json.dumps({'message': 'No S3 records found in event.'})
        }

    s3_record = event['Records'][0]['s3']
    bucket_name = s3_record['bucket']['name']
    object_key = s3_record['object']['key']

    print(f"Processing S3 object: s3://{bucket_name}/{object_key}")
    print(f"Role ARN for Textract SNS Topic: {TEXTRACT_SNS_TOPIC_ROLE_ARN}")
   
    try:
        response = textract_client.start_document_analysis(
            DocumentLocation={
                'S3Object': {
                    'Bucket': bucket_name,
                    'Name': object_key
                }
            },
            FeatureTypes=['FORMS', 'TABLES'],
            
            NotificationChannel={
                'SNSTopicArn': TEXTRACT_SNS_TOPIC_ARN,
                'RoleArn': TEXTRACT_SNS_TOPIC_ROLE_ARN
            },
            
            OutputConfig={
                'S3Bucket': TEXTRACT_OUTPUT_S3_BUCKET
                
            }
        )

        job_id = response['JobId']
        print(f"Successfully started Textract job: {job_id} for s3://{bucket_name}/{object_key}")

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Textract job {job_id} initiated.',
                'jobId': job_id,
                'originalS3Bucket': bucket_name,
                'originalS3Key': object_key
            })
        }

    except Exception as e:
        print(f"Error starting Textract job for {object_key}: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'message': f'Failed to start Textract job: {str(e)}'})
        }

