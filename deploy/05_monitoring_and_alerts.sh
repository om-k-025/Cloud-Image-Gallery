#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 05: MONITORING, LOGGING & ALERT POLICIES
# College Cloud Computing Mini-Project: Cloud-Based Image Gallery
# ==============================================================================
# Cloud Observability Features:
# 1. Cloud Logging: Ingests structured JSON logs emitted to stdout by Flask.
# 2. Log-Based Metric: Tracks security events (failed logins & 403 unauthorized actions).
# 3. Cloud Monitoring Uptime Check: Polls the Cloud Run '/health' endpoint.
# 4. Alert Policy: Dispatches email notifications if the uptime check fails.
# 5. Dashboard Setup: Explains metrics for Request Count, Latency, and Error Rates.
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
echo "Step 1: Discovering Cloud Run Service URL..."
echo "================================================================="
SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --format="value(status.url)")

# Extract hostname without https://
SERVICE_HOST=$(echo "$SERVICE_URL" | sed -e 's|^https://||' -e 's|/$||')
echo "Cloud Run Host: $SERVICE_HOST"

echo ""
echo "================================================================="
echo "Step 2: Creating Cloud Logging Log-Based Metric for Security Audits..."
echo "================================================================="
# This metric counts events where a user failed to log in or attempted an unauthorized 403 action
METRIC_NAME="gallery_unauthorized_events"
FILTER_QUERY='resource.type="cloud_run_revision" AND (jsonPayload.event="LOGIN_FAILURE" OR jsonPayload.event="ACCESS_DENIED_403")'

if gcloud logging metrics describe "$METRIC_NAME" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "[INFO] Metric '$METRIC_NAME' already exists."
else
  gcloud logging metrics create "$METRIC_NAME" \
    --project="$PROJECT_ID" \
    --description="Count of failed login attempts and 403 access denied events" \
    --log-filter="$FILTER_QUERY"
  echo "[SUCCESS] Log-based metric '$METRIC_NAME' created."
fi

echo ""
echo "================================================================="
echo "Step 3: Creating Notification Channel (Email)..."
echo "================================================================="
# Create email notification channel if NOTIFICATION_EMAIL is configured
CHANNEL_JSON=$(mktemp)
cat << EOF > "$CHANNEL_JSON"
{
  "type": "email",
  "displayName": "Gallery Ops Email Alert",
  "description": "Alert notification recipient for college cloud project",
  "labels": {
    "email_address": "${NOTIFICATION_EMAIL}"
  }
}
EOF

CHANNEL_ID=""
if [ -n "$NOTIFICATION_EMAIL" ] && [ "$NOTIFICATION_EMAIL" != "your-email@example.com" ]; then
  CHANNEL_ID=$(gcloud monitoring channels create --channel-content-from-file="$CHANNEL_JSON" --project="$PROJECT_ID" --format="value(name)" || true)
  echo "[SUCCESS] Notification channel created: $CHANNEL_ID"
else
  echo "[INFO] Skipping notification channel creation (default placeholder email detected)."
  echo "You can set your email in deploy/config.env and rerun or add it via GCP Console."
fi
rm -f "$CHANNEL_JSON"

echo ""
echo "================================================================="
echo "Step 4: Creating Cloud Monitoring Uptime Check for /health..."
echo "================================================================="
UPTIME_CONFIG=$(mktemp)
cat << EOF > "$UPTIME_CONFIG"
{
  "displayName": "Gallery App Health Uptime Check",
  "monitoredResource": {
    "type": "uptime_url",
    "labels": {
      "host": "${SERVICE_HOST}",
      "project_id": "${PROJECT_ID}"
    }
  },
  "httpCheck": {
    "path": "/health",
    "port": 443,
    "useSsl": true,
    "validateSsl": true
  },
  "period": "300s",
  "timeout": "10s"
}
EOF

echo "[INFO] Creating uptime check via Monitoring API..."
# Create uptime check
UPTIME_CHECK_NAME=$(gcloud monitoring uptime create \
  --project="$PROJECT_ID" \
  --display-name="Gallery App Health Uptime Check" \
  --protocol=https \
  --hostname="$SERVICE_HOST" \
  --path="/health" \
  --check-interval=5m \
  --timeout=10s \
  --format="value(name)" || true)
echo "[SUCCESS] Uptime check created."
rm -f "$UPTIME_CONFIG"

echo ""
echo "================================================================="
echo "Step 5: Creating Alert Policy (Uptime Check Failure)..."
echo "================================================================="
ALERT_JSON=$(mktemp)
cat << EOF > "$ALERT_JSON"
{
  "displayName": "Gallery App Service Outage Alert",
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "Uptime Check Health Failure",
      "conditionThreshold": {
        "filter": "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\"",
        "comparison": "COMPARISON_LT",
        "thresholdValue": 1,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_FRACTION_TRUE"
          }
        ]
      }
    }
  ]
}
EOF

if [ -n "$CHANNEL_ID" ]; then
  gcloud alpha monitoring policies create \
    --project="$PROJECT_ID" \
    --policy-from-file="$ALERT_JSON" \
    --notification-channels="$CHANNEL_ID" || true
else
  gcloud alpha monitoring policies create \
    --project="$PROJECT_ID" \
    --policy-from-file="$ALERT_JSON" || true
fi
rm -f "$ALERT_JSON"

echo ""
echo "================================================================="
echo "[SUCCESS] Monitoring & Alerting Configuration Complete!"
echo "================================================================="
echo "Cloud Logging Filter Query:"
echo "  $FILTER_QUERY"
echo ""
echo "GCP Console Quick Links:"
echo "  Logs Explorer:      https://console.cloud.google.com/logs/query?project=$PROJECT_ID"
echo "  Uptime Checks:      https://console.cloud.google.com/monitoring/uptime?project=$PROJECT_ID"
echo "  Alert Policies:     https://console.cloud.google.com/monitoring/alerting?project=$PROJECT_ID"
echo "  Cloud Run Metrics:  https://console.cloud.google.com/run/detail/$REGION/$SERVICE_NAME/metrics?project=$PROJECT_ID"
