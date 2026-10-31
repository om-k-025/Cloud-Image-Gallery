#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 04: BUILD CONTAINER & DEPLOY TO GOOGLE CLOUD RUN
# College Cloud Computing Mini-Project: Cloud-Based Image Gallery
# ==============================================================================
# Architecture & Compute:
# - Serverless Container Runtime: Google Cloud Run
# - Ingress: All (public internet via Google-managed HTTPS certificate)
# - Security: Runs under dedicated IAM identity 'gallery-app-sa'
# - Cost Optimization: min-instances=0, max-instances=2 (scales to zero when idle)
# - Resources: 512Mi RAM, 1 vCPU (well within Google Cloud Free Tier)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$SCRIPT_DIR/config.env" ]; then
  source "$SCRIPT_DIR/config.env"
else
  echo "[ERROR] deploy/config.env not found."
  exit 1
fi

APP_SA_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
IMAGE_NAME="gcr.io/${PROJECT_ID}/gallery-app:latest"

echo "================================================================="
echo "Step 1: Building Container Image with Cloud Build..."
echo "Image Target: $IMAGE_NAME"
echo "================================================================="
# Submits the build context from the project root directly to Google Cloud Build
gcloud builds submit "$ROOT_DIR" \
  --project="$PROJECT_ID" \
  --tag="$IMAGE_NAME"

echo ""
echo "================================================================="
echo "Step 2: Deploying Service to Google Cloud Run..."
echo "Service Name: $SERVICE_NAME"
echo "Region: $REGION"
echo "Service Account: $APP_SA_EMAIL"
echo "================================================================="
gcloud run deploy "$SERVICE_NAME" \
  --project="$PROJECT_ID" \
  --image="$IMAGE_NAME" \
  --region="$REGION" \
  --platform=managed \
  --service-account="$APP_SA_EMAIL" \
  --min-instances=0 \
  --max-instances=2 \
  --memory=512Mi \
  --cpu=1 \
  --timeout=60s \
  --ingress=all \
  --allow-unauthenticated \
  --set-env-vars="GCP_PROJECT_ID=${PROJECT_ID},GCS_BUCKET_NAME=${BUCKET_NAME},ADMIN_PASSWORD=${APP_ADMIN_PASSWORD},VIEWER_PASSWORD=${APP_VIEWER_PASSWORD},SECRET_KEY=${APP_SECRET_KEY},LOCAL_STORAGE_MODE=false"

echo ""
echo "================================================================="
echo "Step 3: Retrieving Cloud Run Service URL..."
echo "================================================================="
SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --format="value(status.url)")

echo "-----------------------------------------------------------------"
echo "[SUCCESS] Cloud-Based Image Gallery is live!"
echo "Public HTTPS URL: $SERVICE_URL"
echo "Health Check:     $SERVICE_URL/health"
echo "-----------------------------------------------------------------"
echo "Save this URL for Uptime Check configuration."
echo "Proceed to: ./deploy/05_monitoring_and_alerts.sh"
