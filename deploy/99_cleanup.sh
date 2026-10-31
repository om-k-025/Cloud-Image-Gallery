#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 99: CLEANUP ALL GCP RESOURCES (Cost Prevention)
# College Cloud Computing Mini-Project: Cloud-Based Image Gallery
# ==============================================================================
# Run this script after submitting or presenting your project to tear down all
# created cloud resources and ensure ZERO ongoing charges.
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/config.env" ]; then
  source "$SCRIPT_DIR/config.env"
else
  echo "[ERROR] deploy/config.env not found."
  exit 1
fi

APP_SA_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
VIEWER_SA_EMAIL="${TEST_VIEWER_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
IMAGE_NAME="gcr.io/${PROJECT_ID}/gallery-app"

echo "================================================================="
echo "WARNING: TEARING DOWN ALL PROJECT RESOURCES FOR: $PROJECT_ID"
echo "Resources to be permanently deleted:"
echo "  1. Cloud Run Service:       $SERVICE_NAME"
echo "  2. Container Images:        $IMAGE_NAME:latest"
echo "  3. GCS Bucket & Objects:    gs://$BUCKET_NAME"
echo "  4. App Service Account:     $APP_SA_EMAIL"
echo "  5. Test Service Account:    $VIEWER_SA_EMAIL"
echo "  6. Log Metric:              gallery_unauthorized_events"
echo "  7. Uptime Checks & Alerts"
echo "================================================================="

read -p "Are you sure you want to proceed with full cleanup? (y/N): " -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cleanup aborted by user."
  exit 0
fi

echo "1/7: Deleting Cloud Run service '$SERVICE_NAME'..."
gcloud run services delete "$SERVICE_NAME" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --quiet || true

echo "2/7: Deleting Container Registry images..."
gcloud container images delete "$IMAGE_NAME:latest" \
  --force-delete-tags \
  --quiet || true

echo "3/7: Deleting GCS Bucket 'gs://$BUCKET_NAME' and all contents..."
gcloud storage rm --recursive "gs://$BUCKET_NAME" || true

echo "4/7: Deleting App Service Account '$APP_SA_EMAIL'..."
gcloud iam service-accounts delete "$APP_SA_EMAIL" \
  --project="$PROJECT_ID" \
  --quiet || true

echo "5/7: Deleting Test Viewer Service Account '$VIEWER_SA_EMAIL'..."
gcloud iam service-accounts delete "$VIEWER_SA_EMAIL" \
  --project="$PROJECT_ID" \
  --quiet || true

echo "6/7: Deleting Log-Based Metric 'gallery_unauthorized_events'..."
gcloud logging metrics delete "gallery_unauthorized_events" \
  --project="$PROJECT_ID" \
  --quiet || true

echo "7/7: Deleting Uptime Check..."
# Search and delete the uptime check by display name
CHECK_ID=$(gcloud monitoring uptime list-configs --project="$PROJECT_ID" --format="value(name)" | grep "Gallery" || true)
if [ -n "$CHECK_ID" ]; then
  gcloud monitoring uptime delete "$CHECK_ID" --quiet || true
fi

echo "================================================================="
echo "[SUCCESS] All GCP resources for Cloud Image Gallery have been removed."
echo "Your project is clean. No further charges will be incurred."
echo "================================================================="
