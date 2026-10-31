#!/usr/bin/env bash
# ==============================================================================
# MASTER DEPLOY SCRIPT: RUNS 01 THROUGH 05 IN SEQUENCE
# College Cloud Computing Mini-Project: Cloud-Based Image Gallery
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================================="
echo "Starting Full Automated GCP Deployment for Cloud Image Gallery"
echo "================================================================="

bash "$SCRIPT_DIR/01_create_project_and_enable_apis.sh"
bash "$SCRIPT_DIR/02_create_bucket.sh"
bash "$SCRIPT_DIR/03_create_service_account_and_iam.sh"
bash "$SCRIPT_DIR/04_build_and_deploy_cloud_run.sh"
bash "$SCRIPT_DIR/05_monitoring_and_alerts.sh"

echo "================================================================="
echo "FULL DEPLOYMENT SUCCESSFUL!"
echo "Check docs/README.md and docs/DEMO_SCRIPT.md to proceed with demo."
echo "================================================================="
