# Cloud-Based Image Gallery (GCP Mini-Project)

A lightweight, secure, and production-grade **Cloud-Based Image Gallery** web application built for a college cloud computing mini-project. The project demonstrates core cloud concepts including:
- **Object Storage vs Block Storage** (Google Cloud Storage private bucket).
- **Serverless Containers** (Google Cloud Run) with VM alternative.
- **Identity & Access Management (IAM)** and the **Principle of Least Privilege**.
- **Cryptographic Access Control** using short-lived V4 Signed URLs (10-minute expiry).
- **Cloud Observability** (Cloud Logging structured JSON, log-based metrics, Cloud Monitoring uptime checks & alerting).

---

## 1. Cloud Architecture

```mermaid
flowchart TD
    subgraph ClientLayer ["Client Layer"]
        User["End-User / Auditor Browser"]
    end

    subgraph SecurityPerimeter ["Google Cloud Security Perimeter (Project)"]
        subgraph ComputeLayer ["Compute Layer (Cloud Run)"]
            CloudRun["Cloud Run Service: cloud-image-gallery\n(Flask + Gunicorn Container)\nAutoscale: min 0, max 2"]
            AppSA["IAM Service Account:\ngallery-app-sa"]
            CloudRun -. "Runs as Identity" .-> AppSA
        end

        subgraph StorageLayer ["Object Storage (Cloud Storage)"]
            GCS["Private Cloud Storage Bucket:\ngs://gallery-bucket-PROJECT_ID\n- Uniform Bucket-Level Access: ON\n- Public Access Prevention: ENFORCED"]
        end

        subgraph ObservabilityLayer ["Observability Layer"]
            Logging["Cloud Logging\n(Structured JSON stdout Ingestion)"]
            LogMetric["Log-Based Metric:\ngallery_unauthorized_events"]
            Uptime["Cloud Monitoring\nUptime Check (/health)"]
            AlertPolicy["Email Alert Policy\n(Service Outage Notification)"]
        end
    end

    User -- "1. HTTPS (TLS 1.3)" --> CloudRun
    CloudRun -- "2. List Blobs & Generate V4 Signed URL" --> GCS
    CloudRun -- "3. Return Webpage + Signed URLs" --> User
    User -- "4. Fetch Image via Signed URL (10-min valid)" --> GCS
    User -- "X Direct Access without Signature" -->|HTTP 403 Forbidden| GCS

    CloudRun -- "Logs (JSON to stdout)" --> Logging
    Logging --> LogMetric
    Uptime -- "Polls every 5m" --> CloudRun
    Uptime -. "Trigger Alert on Failure" .-> AlertPolicy
```

### Component Explanations & Design Rationale

| Component | Selected Technology | Why Chosen? |
| :--- | :--- | :--- |
| **Compute** | Google Cloud Run | Serverless container platform that automatically scales down to **0 instances** when idle, incurring **$0.00** during quiet hours. Eliminates OS patching while adhering to modern microservice practices. |
| **Storage** | Google Cloud Storage (Standard) | Highly durable (99.999999999% / 11 9's durability) object storage tailored for unstructured blobs (photos) with native encryption at rest. |
| **Backend** | Python Flask + Gunicorn | Minimal, clean, standard micro-framework that is easy to understand and inspect during college viva evaluations. |
| **Security / IAM** | Dedicated Service Account (`gallery-app-sa`) | Implements the **Principle of Least Privilege**. Never uses default compute identities; granted permissions are scoped strictly to the single bucket. |
| **Content Delivery** | V4 Signed URLs (10-minute validity) | Completely eliminates public bucket exposure. Users never receive raw bucket links; access expires cryptographically after 10 minutes. |
| **Logging** | Google Cloud Logging | Ingests JSON records directly from `stdout`. Automatically indexes event fields like `LOGIN_FAILURE` and `ACCESS_DENIED_403`. |
| **Monitoring** | Cloud Monitoring Uptime Check & Alerts | Continuously tests availability of `/health` every 5 minutes and dispatches alert emails upon downtime. |

---

## 2. Project Directory Structure

```text
c:\Users\Om Kale\Desktop\Cloud Image/
├── app.py                      # Flask application (auth, signed URLs, logging, health check)
├── requirements.txt            # Python dependencies (Flask, Gunicorn, GCS client)
├── Dockerfile                  # Container definition for Cloud Run
├── .env.example                # Template for environment configuration
├── .gitignore                  # Prevents accidental commits of keys and local files
├── templates/
│   ├── base.html               # Shared layout, navbar, flash alerts, role indicators
│   ├── login.html              # Login screen with quick autofill buttons for evaluation
│   ├── gallery.html            # Responsive grid, full-size modal lightbox, signed URL inspector
│   └── upload.html             # Drag-and-drop uploader with client validation & preview
├── static/
│   └── style.css               # Clean modern CSS (glassmorphism, vibrant dark mode)
├── deploy/
│   ├── config.env              # Centralized environment variables for GCP scripts
│   ├── 01_create_project_and_enable_apis.sh
│   ├── 02_create_bucket.sh
│   ├── 03_create_service_account_and_iam.sh
│   ├── 04_build_and_deploy_cloud_run.sh
│   ├── 05_monitoring_and_alerts.sh
│   ├── 99_cleanup.sh           # Full teardown of all resources to avoid costs
│   └── deploy_all.sh           # Master script running 01 to 05 sequentially
└── docs/
    ├── README.md               # Setup and usage guide (this file)
    ├── TECHNICAL_REPORT.md     # Comprehensive academic report with all test cases
    └── DEMO_SCRIPT.md          # 5-minute presentation & viva walkthrough
```

---

## 3. Local Development Quickstart (Run Offline or Online)

The application includes an **Offline Mock Mode** that allows running and testing every role and signed URL locally without any Google Cloud bill or credentials!

### Step 1: Install Dependencies
Open PowerShell or your terminal in the project directory:
```powershell
python -m pip install -r requirements.txt
```

### Step 2: Configure Environment
Copy `.env.example` to `.env`:
```powershell
Copy-Item .env.example .env
```
*(By default, `LOCAL_STORAGE_MODE=true` or offline fallback enables instant local testing without GCP).*

### Step 3: Run the Application
```powershell
python app.py
```
Open your browser to: **http://localhost:8080**

### Demo User Accounts
| Role | Username | Password | Capabilities |
| :--- | :--- | :--- | :--- |
| **Admin** | `admin` | `admin123` | Upload images, View gallery, View full-size, Delete images |
| **Viewer** | `viewer` | `viewer123` | View gallery, View full-size (**Upload & Delete return HTTP 403**) |

*(Click the quick-fill pills on the login page to sign in with one click).*

---

## 4. Google Cloud Deployment (Cloud Run)

The easiest and recommended method is using **Google Cloud Shell** in your web browser (no local installation needed):

1. Open [Google Cloud Shell](https://shell.cloud.google.com).
2. Upload this project folder or clone your repository.
3. Edit `deploy/config.env` with your GCP Project ID and alert notification email:
   ```bash
   nano deploy/config.env
   ```
4. Run the automated deployment script:
   ```bash
   chmod +x deploy/*.sh
   ./deploy/deploy_all.sh
   ```
5. The terminal will output your live HTTPS Cloud Run URL (e.g. `https://cloud-image-gallery-xyz-uc.a.run.app`).

---

## 5. Alternative Compute Engine VM Deployment

If your syllabus requires running on a Virtual Machine instead of Cloud Run:

1. **Create Compute Engine VM with attached service account:**
   ```bash
   gcloud compute instances create gallery-vm \
     --zone=us-central1-a \
     --machine-type=e2-micro \
     --service-account=gallery-app-sa@$PROJECT_ID.iam.gserviceaccount.com \
     --scopes=cloud-platform \
     --tags=http-server,https-server \
     --image-family=debian-12 \
     --image-project=debian-cloud
   ```
2. **Create Firewall Rule (Least Privilege Network Rules):**
   ```bash
   # Allow HTTP/HTTPS only; restrict SSH to your public IP
   MY_IP=$(curl -s https://ifconfig.me)
   gcloud compute firewall-rules create allow-http-https \
     --allow=tcp:80,tcp:443 \
     --target-tags=http-server,https-server \
     --description="Allow public web traffic to gallery app"

   gcloud compute firewall-rules create allow-ssh-admin \
     --allow=tcp:22 \
     --source-ranges="${MY_IP}/32" \
     --description="Allow SSH strictly from admin IP address"
   ```
3. **SSH and Launch App:**
   ```bash
   gcloud compute ssh gallery-vm --zone=us-central1-a
   # Inside VM:
   sudo apt-get update && sudo apt-get install -y python3-pip git
   git clone <your-repo> && cd "Cloud Image"
   pip3 install -r requirements.txt
   export GCS_BUCKET_NAME="gallery-bucket-YOUR_PROJECT"
   gunicorn --bind 0.0.0.0:80 app:app
   ```

---

## 6. Project Checklist & Verification Matrix

| # | Project Milestone | Satisfying Files / Commands | Verification Status |
| :---: | :--- | :--- | :---: |
| **1** | **Create Project & APIs** | `deploy/01_create_project_and_enable_apis.sh` | [x] Cloud Run, Storage, IAM, Logging, Monitoring APIs enabled |
| **2** | **Storage Setup** | `deploy/02_create_bucket.sh` | [x] Private bucket, Uniform Access ON, Public Access PREVENTED |
| **3** | **Deploy Application** | `Dockerfile`, `deploy/04_build_and_deploy_cloud_run.sh` | [x] Cloud Run container live with HTTPS and autoscaling (0-2) |
| **4** | **Configure App** | `app.py`, `.env.example`, `templates/` | [x] RBAC, 5MB image validator, modern Jinja UI, /health route |
| **5** | **IAM Least Privilege** | `deploy/03_create_service_account_and_iam.sh` | [x] Dedicated SA with bucket-scoped objectAdmin & test viewer SA |
| **6** | **Network & Security** | `deploy/02_create_bucket.sh`, `deploy/04_build_and_deploy_cloud_run.sh` | [x] HTTPS enforced, Public access blocked, Signed URLs only |
| **7** | **Monitoring & Logs** | `deploy/05_monitoring_and_alerts.sh`, `app.py` | [x] JSON logs to stdout, Uptime check on /health, Outage alert |
| **8** | **Testing Suite** | `docs/TECHNICAL_REPORT.md` (Section 11) | [x] Normal + Unauthorized curl and manual test cases defined |
| **9** | **Screenshots Guide** | `docs/TECHNICAL_REPORT.md` (Section 12) | [x] Complete list of console screenshots with placeholders |
| **10**| **Resource Cleanup** | `deploy/99_cleanup.sh` | [x] 1-click teardown script to delete all resources |

---

## 7. Teardown / Cost Prevention

To delete all resources and ensure zero billing after project submission:
```bash
./deploy/99_cleanup.sh
```
