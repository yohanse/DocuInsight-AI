FROM python:3.9-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install minimal system packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Python libraries with correct versions
RUN pip install --no-cache-dir \
    torch==2.1.2+cpu -f https://download.pytorch.org/whl/cpu/torch_stable.html \
    sentence-transformers==2.2.2 \
    huggingface-hub==0.18.0 \
    flask

# Create working directory
WORKDIR /app

# Copy model server and entrypoint
COPY serve /usr/bin/serve
COPY app.py .

RUN chmod +x /usr/bin/serve

# Entrypoint for SageMaker or manual run
ENTRYPOINT ["serve"]
