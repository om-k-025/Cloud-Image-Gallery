#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 03: SERVICE ACCOUNT PROVISIONING & LEAST-PRIVILEGE IAM
# College Cloud Computing Mini-Project: Cloud-Based Image Gallery
# ==============================================================================
# Security Principles Demonstrated:
# 1. Principle of Least Privilege: Never use the Compute Engine Default Service Account,
#    which by default possesses broad Project Editor privileges.
# 2. Scoped Permissions: 'roles/storage.objectAdmin' is granted ONLY on 'gs://$BUCKET_NAME',
#    NOT project-wide! It cannot access any other bucket in the GCP project.
# 3. Cryptographic Token Creator: Grants 'roles/iam.serviceAccountTokenCreator'
#    to the service account on itself. This allows the Cloud Run container to generate
#    V4 Signed URLs dynamically via the GCP IAM Credentials API without storing any
#    private JSON keys inside the container image or filesystem!
# 4. Separation of Duties (Test Identity): A secondary service account
#    ('gallery-test-viewer-sa') is created with read-only 'roles/storage.objectViewer'
#    to prove in test cases that upload/delete requests from a viewer identity fail.
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

echo "================================================================="
echo "Step 1: Creating Dedicated Service Account: $SERVICE_ACCOUNT_NAME"
echo "================================================================="
if gcloud iam service-accounts describe "$APP_SA_EMAIL" >/dev/null 2>&1; then
  echo "[INFO] Service account '$APP_SA_EMAIL' already exists."
else
  gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
    --project="$PROJECT_ID" \
    --display-name="Cloud Gallery App Runtime Identity" \
    --description="Least-privilege runtime identity for Cloud Run gallery container"
  echo "[SUCCESS] Service account '$APP_SA_EMAIL' created."
fi

echo ""
echo "================================================================="
echo "Step 2: Binding BUCKET-SCOPED Object Admin Role (Least Privilege)..."
echo "================================================================="
# CRITICAL: We bind roles/storage.objectAdmin strictly to the SINGLE bucket, NOT project-wide!
gcloud storage buckets add-iam-policy-binding "gs://$BUCKET_NAME" \
  --member="serviceAccount:$APP_SA_EMAIL" \
  --role="roles/storage.objectAdmin"

echo "[SUCCESS] Granted 'roles/storage.objectAdmin' to '$APP_SA_EMAIL' strictly on 'gs://$BUCKET_NAME'."

echo ""
echo "================================================================="
echo "Step 3: Granting Token Creator Role on Itself (for V4 Signed URLs)..."
echo "================================================================="
# Why is this role needed?
# In Cloud Run, applications run without downloaded JSON private keys.
# To generate V4 Signed URLs, the Google Cloud client library invokes the IAM Credentials
# API (signBlob method) to cryptographically sign the URL. The service account needs
# permission to sign blobs on its own behalf.
gcloud iam service-accounts add-iam-policy-binding "$APP_SA_EMAIL" \
  --member="serviceAccount:$APP_SA_EMAIL" \
  --role="roles/iam.serviceAccountTokenCreator"

echo "[SUCCESS] Granted 'roles/iam.serviceAccountTokenCreator' to '$APP_SA_EMAIL' on itself."

echo ""
echo "================================================================="
echo "Step 4: Creating Test Viewer Identity (Demonstrating Least Privilege)..."
echo "================================================================="
# This secondary identity demonstrates least-privilege isolation:
# It possesses only 'roles/storage.objectViewer' (read-only) on the bucket.
if gcloud iam service-accounts describe "$VIEWER_SA_EMAIL" >/dev/null 2>&1; then
  echo "[INFO] Test viewer service account '$VIEWER_SA_EMAIL' already exists."
else
  gcloud iam service-accounts create "$TEST_VIEWER_SA_NAME" \
    --project="$PROJECT_ID" \
    --display-name="Test Viewer Read-Only Identity" \
    --description="Used in Test Case TC-09 to prove upload/delete rejection"
fi

gcloud storage buckets add-iam-policy-binding "gs://$BUCKET_NAME" \
  --member="serviceAccount:$VIEWER_SA_EMAIL" \
  --role="roles/storage.objectViewer"

echo "[SUCCESS] Created test viewer identity '$VIEWER_SA_EMAIL' with read-only bucket access."

echo ""
echo "================================================================="
echo "IAM POLICY SUMMARY FOR BUCKET 'gs://$BUCKET_NAME':"
echo "================================================================="
gcloud storage buckets get-iam-policy "gs://$BUCKET_NAME" --format="table(bindings.role, bindings.members)"

echo ""
echo "[SUCCESS] IAM provisioning complete."
echo "Proceed to: ./deploy/04_build_and_deploy_cloud_run.sh"
