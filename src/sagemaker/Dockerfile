# src/sagemaker_model/Dockerfile

# --- Stage 1: Builder Stage ---
# This stage installs all Python dependencies, including large ones like torch.
# We use a python:3.10-slim-bullseye image as it has active apt repositories.
FROM python:3.10-slim-bullseye AS builder

# Prevent Python from writing .pyc files and ensure unbuffered output
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# Set working directory for the builder stage
WORKDIR /app

# Install system dependencies needed for building Python packages (like torch)
# and clean up apt cache immediately to keep this stage lean.
# libgomp1 is often required for torch on CPU in Debian-based images.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Copy only the requirements file first to leverage Docker layer caching.
# If requirements.txt doesn't change, this layer won't rebuild.
COPY requirements.txt .

# Install Python dependencies from requirements.txt.
# --no-cache-dir reduces the size of this layer by not storing pip's cache.
RUN pip install --no-cache-dir -r requirements.txt

# Copy your application code (app.py)
COPY app.py .

# --- Stage 2: Final Runtime Stage ---
# This stage creates the final, lean image for deployment.
# It copies only the necessary application code and installed Python packages from the builder.
FROM python:3.10-slim-bullseye

# Prevent Python from writing .pyc files and ensure unbuffered output
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# Set working directory for the final image.
# /opt/ml/code is the standard location for SageMaker custom containers.
WORKDIR /opt/ml/code

# Copy the application code from the builder stage
COPY --from=builder /app/app.py .

# Copy only the installed Python packages from the builder stage's site-packages.
# This avoids copying build-essential and other temporary files from the builder stage.
COPY --from=builder /usr/local/lib/python3.10/site-packages /usr/local/lib/python3.10/site-packages

# Set environment variables expected by SageMaker for custom inference code.
# These tell SageMaker's serving container where to find your entry point.
ENV SAGEMAKER_PROGRAM app.py
ENV SAGEMAKER_SUBMIT_DIRECTORY /opt/ml/code

# Expose port 8080 as SageMaker's default serving container expects this.
EXPOSE 8080

# Command to run your Flask application when the container starts.
# This assumes your app.py starts a Flask server on 0.0.0.0:8080.
# This CMD is compatible with the Flask server you defined in app.py.
CMD ["python", "app.py"]