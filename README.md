DocuInsight AI: My Serverless Document Brain! 🧠📄
Hey there! This is my personal project, DocuInsight AI. It's like, my attempt to build a smart little system that can read my documents, understand what's inside, and then let me ask questions about them in plain English. Kinda cool, right?

I've been applying for jobs at big tech places like Amazon and Google for a while now (three years, phew!), and I figured, instead of just talking about cloud and AI, I should build something real. So, this is it!

What is this thing? (The Big Idea)
Basically, I wanted a way to just dump documents somewhere and have them magically become searchable. Not just keyword search, but like, "find me the total amount on that invoice from last month for Acme Corp." kind of search. So, this project is a serverless pipeline that:

Automatically takes documents I upload.

Pulls out all the text, forms, and tables using some fancy AI.

Turns that text into "embeddings" (which are like, numerical representations that AI understands for meaning).

Stores everything in a smart database.

Lets me ask questions using natural language, and it finds the relevant stuff.

It's all built on AWS, and I've tried really hard to keep it in the Free Tier. Cause, you know, bills. 😅

How it's Built (The Techy Bits)
This project uses a bunch of AWS services, and I'm using Terraform for all the infrastructure stuff, and GitHub Actions for CI/CD. It's a proper setup, even if it's just me working on it!

Architecture (Rough Sketch, imagine a cool diagram here!)
+----------------+     +-----------------------+     +----------------------+
|    User Upload | --> | S3 Input Bucket (Doc) | --> | S3 Event Notification|
+----------------+     +-----------------------+     +----------------------+
                                   |
                                   V
+--------------------------+     +-----------------------+
| AWS Lambda (Orchestrator)| --> | SQS Queue (Textract Job)|
+--------------------------+     +-----------------------+
           |                                 |
           V                                 V
+--------------------------+     +-----------------------+
| Amazon Textract          | --> | S3 Output Bucket (JSON)|
+--------------------------+     +-----------------------+
           |
           V (Textract Completion Notification)
+--------------------------+
| AWS Lambda (Processor)   |
+--------------------------+
           |
           V
+--------------------------+     +-----------------------+
| Amazon SageMaker         | --> | Amazon OpenSearch     |
| (Serverless Embeddings)  |     | (Vector & Full-Text)  |
+--------------------------+     +-----------------------+
           |                                 ^
           V                                 |
+--------------------------+                 |
| Amazon DynamoDB          |                 |
| (Metadata Storage)       |                 |
+--------------------------+                 |
                                             |
+--------------------------+     +-----------------------+
| User Query (API Gateway) | --> | AWS Lambda (Query API)|
+--------------------------+     +-----------------------+

(Yeah, I know, I need to make a proper diagram. It's on the list!)

Technologies Used
Cloud Platform: AWS (Amazon Web Services)

Infrastructure as Code (IaC): Terraform (for everything!)

CI/CD: GitHub Actions (automating deployments, yay!)

Storage: Amazon S3 (for raw docs and Textract output)

AI/ML Services:

Amazon Textract: For OCR, form, and table extraction. It's pretty smart!

Amazon SageMaker (Serverless Inference): This is where the magic happens for turning text into embeddings for semantic search. I'm using a pre-trained sentence-transformers model.

Databases/Search:

Amazon DynamoDB: For storing document metadata (like filenames, IDs, and key extracted fields).

Amazon OpenSearch Service: This is my search engine. It handles both regular keyword search and the fancy vector (semantic) search.

Serverless Compute: AWS Lambda (Python for all the logic)

API: Amazon API Gateway (to expose my natural language query endpoint)

Messaging: Amazon SNS & SQS (for asynchronous stuff, so things don't break if one part is slow)

Monitoring: Amazon CloudWatch (for logs and keeping an eye on things)

Getting Started (How to Run This Beast)
Prerequisites
You'll need these installed on your machine:

AWS CLI (configured with admin access for simplicity in a personal project)

Terraform CLI

Python 3.x

Git

Docker Desktop (for SageMaker model image)

Setup & Deployment
Clone this repo:

git clone https://github.com/your-username/DocuInsight-AI.git
cd DocuInsight-AI

AWS Account & Billing Alerts: Make sure you have an AWS account and PLEASE, PLEASE, PLEASE set up billing alerts. I've tried my best to stay Free Tier, but some services have time limits.

Terraform Backend:

Manually create an S3 bucket (e.g., your-account-id-tfstate-doc-ai) and a DynamoDB table (e.g., your-account-id-tf-lock-doc-ai) in your AWS console for Terraform state.

Update infrastructure/backend.tf with your bucket and table names.

cd infrastructure

terraform init

SageMaker Model Build & Push (First Time Only):

cd ../src/sagemaker_model

docker build -t your-ecr-repo-name:latest . (Replace your-ecr-repo-name with what Terraform will create)

Log in to ECR: aws ecr get-login-password --region your-aws-region | docker login --username AWS --password-stdin your-aws-account-id.dkr.ecr.your-aws-region.amazonaws.com

docker push your-ecr-repo-name:latest

GitHub Actions Secrets: In your GitHub repo settings, add AWS_REGION, TF_BACKEND_BUCKET, TF_BACKEND_DYNAMODB_TABLE. Set up OIDC for AWS authentication (super important for security!).

Deploy with CI/CD: Just push your code to the main branch! GitHub Actions will take care of the rest.

git add .

git commit -m "Initial deployment"

git push origin main

Go to the "Actions" tab in GitHub and watch the magic happen!

How to Use It
Upload Documents: Once deployed, upload some small PDF or JPG documents (1-2 pages each, keep it light for Free Tier!) to the S3 input bucket that Terraform created.

Query: Get the API Gateway URL from your Terraform outputs. Then, use curl or Postman to send a natural language query:

curl -X POST -H "Content-Type: application/json" \
-d '{"query": "What is the total amount on the invoice from John Doe?"}' \
YOUR_API_GATEWAY_INVOKE_URL/query

Replace the URL with your actual API Gateway endpoint.

Free Tier Considerations (Read This! Seriously!)
I built this with the AWS Free Tier in mind, but you gotta be careful. Here's what to watch out for:

Textract: Only 3 months free for new accounts, and the page limits are very small for AnalyzeDocument (100 pages/month). DetectDocumentText is more generous (1,000 pages/month). Don't go wild with document uploads!

SageMaker Serverless Inference: Only 2 months free (150,000 seconds of inference). After that, it'll cost you. If you're not actively using the project after the first two months, consider tearing down the SageMaker endpoint with Terraform to avoid charges.

OpenSearch: 12 months free for a t3.small.search instance (only one instance!). After a year, this will start costing money. Keep your data volume low (<10GB).

Billing Alerts: I already said this, but set them up! They're your best friend.

Clean Up: When you're done playing around or if you're taking a break, run terraform destroy to delete everything. Then, manually double-check S3 buckets and DynamoDB tables to make sure nothing is left behind.

Lessons Learned (My Journey So Far)
Building this has been a wild ride! A few things I've learned:

Free Tier is Tricky: It's awesome for learning, but you really have to understand the limits. It's easy to accidentally go over, especially with AI services.

Asynchronous is Key: For services like Textract, using asynchronous calls is way better. It makes your Lambdas faster and more resilient.

IaC is a Lifesaver: Terraform makes deploying and updating so much easier. No more clicking around in the console for hours!

Debugging Distributed Systems: When you have so many services talking to each other, figuring out where a problem is can be a puzzle. CloudWatch logs are essential.

Vector Search is Powerful: Seriously, semantic search is a game-changer for finding relevant information, not just keywords.

Future Enhancements (Ideas for Next Steps)
Build a simple web UI (maybe React or Vue) to make it easier to upload documents and send queries.

Add more sophisticated error handling and dead-letter queues (DLQs) for all Lambdas.

Implement more advanced natural language processing (NLP) on the extracted text before indexing (e.g., entity recognition, summarization).

Integrate with other data sources, not just documents.

Add user authentication and authorization.

About Me
I'm a passionate (and sometimes frustrated!) aspiring cloud/DevOps engineer. I've been working hard to break into the tech industry, and I love building things that solve real problems. If you have any feedback or just wanna chat about cloud stuff, feel free to reach out!

Your Name Here
Your LinkedIn Profile Link
Your Personal Website/Blog (if you have one)