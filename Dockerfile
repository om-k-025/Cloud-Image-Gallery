# ==============================================================================
# Cloud-Based Image Gallery - Production Dockerfile for Google Cloud Run
# ==============================================================================
# Base image: Official lightweight Python slim image
FROM python:3.11-slim

# Prevent Python from writing .pyc files and enable unbuffered logging to stdout
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PORT=8080

# Set working directory inside container
WORKDIR /app

# Install system dependencies (curl for health checks, clean up cache after)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first to leverage Docker layer caching
COPY requirements.txt .

# Install Python packages
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source code
COPY app.py .
COPY templates/ ./templates/
COPY static/ ./static/

# Cloud Run injects the $PORT environment variable (defaults to 8080)
EXPOSE 8080

# Production web server: Gunicorn with threaded worker model
# - 1 worker process with 8 concurrent threads (recommended for I/O-bound cloud storage requests)
# - timeout 0 to avoid container worker timeouts during cold starts
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 app:app
