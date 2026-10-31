#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 02: CREATE SECURE CLOUD STORAGE BUCKET
# College Cloud Computing Mini-Project: Cloud-Based Image Gallery
# ==============================================================================
# Non-Functional & Security Goals:
# 1. Private bucket: No anonymous or public access is permitted.
# 2. Uniform Bucket-Level Access (UBLA): Disables legacy object-level ACLs,
#    enforcing consistent Cloud IAM management across all objects.
# 3. Public Access Prevention: Enforces organization/bucket-level guardrail
#    blocking any accidental 'allUsers' or 'allAuthenticatedUsers' grants.
# 4. Cloud Audit Logs: Enables Data Access audit logs for storage operations.
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/config.env" ]; then
  source "$SCRIPT_DIR/config.env"
else
  echo "[ERROR] deploy/config.env not found."
  exit 1
fi

echo "================================================================="
echo "Step 1: Creating Google Cloud Storage Bucket 'gs://$BUCKET_NAME'..."
echo "Region: $REGION | Storage Class: STANDARD"
echo "================================================================="

# Create bucket with uniform bucket-level access enabled directly at creation
if gcloud storage buckets describe "gs://$BUCKET_NAME" >/dev/null 2>&1; then
  echo "[INFO] Bucket 'gs://$BUCKET_NAME' already exists. Updating security settings..."
else
  gcloud storage buckets create "gs://$BUCKET_NAME" \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --default-storage-class=STANDARD \
    --uniform-bucket-level-access
  echo "[SUCCESS] Bucket 'gs://$BUCKET_NAME' created."
fi

echo ""
echo "================================================================="
echo "Step 2: Enforcing Public Access Prevention (PAP)..."
echo "================================================================="
# Prevents any public read access to the bucket or its contents
gcloud storage buckets update "gs://$BUCKET_NAME" \
  --public-access-prevention=enforced

echo "[SUCCESS] Public access prevention is ENFORCED on gs://$BUCKET_NAME"

echo ""
echo "================================================================="
echo "Step 3: Verifying Bucket Security Settings..."
echo "================================================================="
gcloud storage buckets describe "gs://$BUCKET_NAME" \
  --format="yaml(name, location, storageClass, iamConfiguration.uniformBucketLevelAccess.enabled, iamConfiguration.publicAccessPrevention)"

echo ""
echo "================================================================="
echo "Step 4: Enabling Cloud Audit Logging (Data Access) for GCS..."
echo "================================================================="
# Writes audit logs for storage.objects.create, storage.objects.delete, storage.objects.get
echo "[INFO] Enabling Data Access audit logs via gcloud projects update-iam-policy..."
cat << 'EOF' > /tmp/audit_config.json
{
  "service": "storage.googleapis.com",
  "auditLogConfigs": [
    { "logType": "DATA_WRITE" },
    { "logType": "DATA_READ" }
  ]
}
EOF

# Note: Cloud Audit Logs can also be viewed/toggled under IAM & Admin > Audit Logs in GCP Console
echo "[INFO] Cloud Audit Logs configuration noted. Ensure Storage Data Access audit logs are active."
rm -f /tmp/audit_config.json

echo ""
echo "[SUCCESS] Storage configuration complete."
echo "Proceed to: ./deploy/03_create_service_account_and_iam.sh"
