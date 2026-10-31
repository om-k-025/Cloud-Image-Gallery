#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 01: PROJECT SETUP & API ENABLING
# College Cloud Computing Mini-Project: Cloud-Based Image Gallery
# ==============================================================================
# This script sets the active GCP project context and enables all required
# Cloud APIs following Google Cloud best practices.
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/config.env" ]; then
  source "$SCRIPT_DIR/config.env"
else
  echo "[ERROR] deploy/config.env not found. Please create it first."
  exit 1
fi

echo "================================================================="
echo "Step 1: Setting GCP Project context to '$PROJECT_ID'..."
echo "================================================================="
gcloud config set project "$PROJECT_ID"

echo ""
echo "================================================================="
echo "Step 2: Enabling Required GCP APIs..."
echo "================================================================="
# 1. run.googleapis.com: Cloud Run serverless container runtime
# 2. storage.googleapis.com: Google Cloud Storage for blob/image hosting
# 3. cloudbuild.googleapis.com: Builds container images directly in GCP
# 4. logging.googleapis.com: Centralized stdout logging and metric filters
# 5. monitoring.googleapis.com: Uptime checks and latency/error alerting
# 6. iam.googleapis.com: Service accounts and least-privilege role binding
# 7. iamcredentials.googleapis.com: Allows generating V4 signed URLs without local keys
echo "Enabling: Cloud Run, Cloud Storage, Cloud Build, Cloud Logging, Cloud Monitoring, IAM..."

gcloud services enable \
  run.googleapis.com \
  storage.googleapis.com \
  cloudbuild.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com

echo ""
echo "[SUCCESS] All required Google Cloud APIs have been enabled for project '$PROJECT_ID'."
echo "Proceed to: ./deploy/02_create_bucket.sh"
