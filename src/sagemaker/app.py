import os
import json
from flask import Flask, request, jsonify
from sentence_transformers import SentenceTransformer
import torch # PyTorch is a dependency of sentence-transformers

# Initialize Flask app
app = Flask(__name__)

# Global variable to hold the loaded model.
# This ensures the model is loaded only once when the container starts (cold start).
model = None

# --- SageMaker Specific Functions ---
# SageMaker's serving container will look for these functions
# when it starts up and when it receives inference requests.

def model_fn(model_dir):
    """
    Loads the pre-trained SentenceTransformer model.
    This function is called by SageMaker when the container starts.

    Args:
        model_dir (str): The directory where SageMaker expects model artifacts.
                         For this example, we're downloading the model, so model_dir isn't directly used
                         to load from a local path, but it's a required argument.
    Returns:
        SentenceTransformer: The loaded SentenceTransformer model.
    """
    print(f"Loading SentenceTransformer model 'all-MiniLM-L6-v2'...")
    # 'all-MiniLM-L6-v2' is a small, efficient, and effective model for embeddings.
    # The SentenceTransformer library will download it if not already cached.
    global model
    model = SentenceTransformer('all-MiniLM-L6-v2')
    print("Model loaded successfully.")
    return model

def predict_fn(input_data, model):
    """
    Performs inference (embedding generation) on the input data using the loaded model.
    This function is called by SageMaker for each inference request.

    Args:
        input_data (str or list[str]): The text string(s) to be embedded.
        model (SentenceTransformer): The loaded SentenceTransformer model.

    Returns:
        list[list[float]]: A list of embedding vectors (each vector is a list of floats).
    """
    print(f"Received input data for prediction: {input_data[:100]}...") # Log first 100 chars
    
    # Ensure input_data is a list of strings, as the model expects
    if isinstance(input_data, str):
        input_data = [input_data]
    elif not isinstance(input_data, list) or not all(isinstance(item, str) for item in input_data):
        raise ValueError("Input data must be a string or a list of strings.")

    # Generate embeddings. convert_to_tensor=True returns PyTorch tensors.
    # We then convert them to a list of lists for JSON serialization.
    embeddings = model.encode(input_data, convert_to_tensor=True)
    return embeddings.tolist()

# --- Flask Endpoints for Serving ---
# These endpoints define the API for your Docker container.
# SageMaker's serving infrastructure interacts with these.

@app.route('/ping', methods=['GET'])
def ping():
    """
    Health check endpoint.
    SageMaker calls this endpoint to check if the container is healthy and ready to serve requests.
    """
    print("Ping received. Responding with OK.")
    return jsonify(status='OK'), 200

@app.route('/invocations', methods=['POST'])
def invocations():
    """
    Inference endpoint.
    SageMaker sends actual inference requests to this endpoint.
    It expects a JSON payload with a 'text' key or plain text.
    """
    print(f"Invocations request received. Content-Type: {request.content_type}")

    input_data = None
    if request.content_type == 'application/json':
        try:
            payload = request.json
            input_data = payload.get('text')
            if not input_data:
                return jsonify(error='Missing "text" field in JSON payload'), 400
        except Exception as e:
            print(f"Error parsing JSON: {e}")
            return jsonify(error='Invalid JSON payload'), 400
    elif request.content_type == 'text/plain':
        input_data = request.data.decode('utf-8')
    else:
        # Return a 415 Unsupported Media Type if the content type is not supported
        return jsonify(error=f'Unsupported content type: {request.content_type}'), 415

    # Ensure the model is loaded before prediction (important for local testing)
    # In SageMaker, model_fn is called automatically on container startup.
    global model
    if model is None:
        try:
            model = model_fn(None) # Load the model if not already loaded
        except Exception as e:
            print(f"Error loading model during invocation: {e}")
            return jsonify(error=f"Model loading failed: {str(e)}"), 500

    try:
        # Call the predict_fn with the input data and loaded model
        predictions = predict_fn(input_data, model)
        # Return the embeddings as a JSON response
        return jsonify(embeddings=predictions), 200
    except ValueError as ve:
        print(f"Validation error in prediction: {ve}")
        return jsonify(error=str(ve)), 400
    except Exception as e:
        print(f"Prediction error: {e}")
        return jsonify(error=f"Prediction failed: {str(e)}"), 500

# --- Main execution for local testing ---
if __name__ == '__main__':
    # When running locally, load the model when the Flask app starts.
    # SageMaker handles this via model_fn on container startup.
    model_fn(None) # Call model_fn to load the model
    
    # Run the Flask app on port 8080, which SageMaker expects.
    print("Starting Flask app for local testing on http://0.0.0.0:8080")
    app.run(host='0.0.0.0', port=8080)
