# 5-Minute Project Demonstration & Viva Script
**Project:** Cloud-Based Image Gallery (GCP Mini-Project)  
**Target Audience:** Professor, Internal / External Examiner, Evaluator  
**Total Duration:** 5 Minutes  

---

## Quick Reference / Demo Prep Checklist
Before beginning your presentation, ensure you have these browser tabs open:
1. **Tab 1:** Live Cloud Run Web App (`https://cloud-image-gallery-...a.run.app` or `http://localhost:8080`)
2. **Tab 2:** GCP Cloud Storage Console (Buckets > `gallery-bucket-...`)
3. **Tab 3:** GCP Cloud Logging Console (Logs Explorer)
4. **Tab 4:** GCP Cloud Monitoring Console (Uptime Checks)
5. **Sample Image:** Prepare a test image (e.g. `sample.jpg` < 5 MB) on your desktop.

---

## Minute 1: Introduction & Architectural Overview (0:00 - 1:00)

### What to Say:
> *"Good morning/afternoon, professors. Today I am presenting my Cloud Computing mini-project: a **Cloud-Based Image Gallery** built on Google Cloud Platform.*
> 
> *Traditional web applications suffer from storing uploaded files on local server hard disks, which creates single points of failure, doesn't scale across instances, and often exposes buckets publicly.*
> 
> *In this project, I decoupled compute from storage using a modern cloud-native architecture:*
> 1. *Our compute layer runs on **Google Cloud Run** as a lightweight containerized microservice that automatically scales down to zero instances to conserve costs.*
> 2. *Our storage layer uses **Google Cloud Storage** with **Uniform Bucket-Level Access** and **Public Access Prevention enforced**.*
> 3. *Crucially, we enforce the **Principle of Least Privilege**: our dedicated service account has permissions scoped **strictly to this single bucket**, not the entire project.*
> 4. *Images are never public—they are delivered exclusively through **short-lived 10-minute V4 cryptographic signed URLs**."*

### What to Show:
- Open the Mermaid Architecture Diagram in `docs/README.md` or present a slide showing the flow:  
  `Client Browser -> HTTPS -> Cloud Run -> Private GCS Bucket -> V4 Signed URLs`.

---

## Minute 2: Admin Workflow & Image Lifecycle (1:00 - 2:00)

### What to Say:
> *"Let's begin by testing our administrative workflow. The application features Role-Based Access Control (RBAC). I will sign in as the Administrator."*

### What to Do:
1. Navigate to `/login`.
2. Click the quick-fill pill **"Admin User"** (or type `admin` / `admin123`) and click **Sign In**.
3. Point out the top-right header: **"Admin User [ADMIN]"** badge and the **"10-Min Signed URLs"** indicator.
4. Click **"Upload New Image"**.
5. Drag and drop your test image (`sample.jpg`). Point out:
   - Instant client-side preview.
   - Format and 5 MB size limit validation.
6. Click **"Upload to Cloud"**.
7. In the gallery grid:
   - Click the thumbnail: notice the **Modal Lightbox** opening full-screen.
   - Right-click or copy the **"Signed Link"** button and highlight the URL query parameters:
     > *"Notice that this URL includes `X-Goog-Algorithm`, `X-Goog-Expires=600`, and `X-Goog-Signature`. This link expires in exactly 10 minutes."*
8. Delete the image using the red **"Delete"** button to confirm end-to-end admin CRUD capability.

---

## Minute 3: Viewer Workflow & 403 Security Enforcement (2:00 - 3:00)

### What to Say:
> *"Now let's demonstrate role separation and least privilege. I will log out and sign in with the Viewer role."*

### What to Do:
1. Click **"Logout"** in the top navigation bar.
2. Click the **"Viewer User"** quick-fill pill (`viewer` / `viewer123`) and log in.
3. Show the UI changes:
   - Role badge updates to **"Viewer User [VIEWER]"**.
   - Notice that the **"+ Upload New Image"** and **"Delete"** buttons are completely hidden from the viewer's interface.
4. **Trigger Security Enforcement:**
   > *"What happens if a malicious user bypasses the UI and forces a request to an admin endpoint? Let's manually navigate to `/upload`."*
5. In the browser address bar, type: `.../upload` and hit Enter.
6. Show the response:
   - The application immediately returns an explicit **HTTP 403 Forbidden / Access Denied** alert:  
     `"Access Denied: Role 'admin' required. Current role is 'viewer'."`
   > *"The server intercepted the unauthorized request, blocked execution, and wrote a security audit event to our cloud logs."*

---

## Minute 4: GCP Console Proofs - Cloud Storage & Scoped IAM (3:00 - 4:00)

### What to Say:
> *"Now let's verify our cloud infrastructure inside the Google Cloud Console to prove our security configurations."*

### What to Do:
1. Switch to **Tab 2 (Cloud Storage Console)**:
   - Show the bucket name: `gallery-bucket-[PROJECT_ID]`.
   - Click **Configuration**: Point to **Uniform bucket-level access: Enabled** and **Public access prevention: Enforced**.
   - Copy the direct bucket link (`https://storage.googleapis.com/.../file.jpg`) and open it in a private window:
     > *"Notice that direct access returns an XML `AccessDenied` error from Google. The bucket cannot be leaked publicly."*
2. Click **Permissions** tab on the bucket:
   - Show that `gallery-app-sa` is assigned `Storage Object Admin` **only on this specific bucket**, proving least-privilege scoping.
   - Point out the secondary test account `gallery-test-viewer-sa` with read-only viewer rights.

---

## Minute 5: Cloud Observability, Uptime Alerting & Wrap-Up (4:00 - 5:00)

### What to Say:
> *"Finally, let's look at observability and cost control."*

### What to Do:
1. Switch to **Tab 3 (Cloud Logging)**:
   - Run the filter: `jsonPayload.event="ACCESS_DENIED_403"`
   - Expand the JSON payload:
     > *"Here is the structured log event generated when our viewer attempted the unauthorized upload. It captures the timestamp, IP address, user role, and attempted path."*
2. Switch to **Tab 4 (Cloud Monitoring)**:
   - Show the **Uptime Check** for `/health`: green status icon with latency graphs.
   - Mention the alert policy configured to notify via email if the service ever goes down.
3. **Closing Statement:**
   > *"In summary, this project demonstrates end-to-end cloud engineering: a containerized microservice on Cloud Run, secure object storage with signed URLs, strict IAM least-privilege governance, and automated observability—all operating completely within the GCP Always Free Tier.*
   > 
   > *When our project evaluation is finished, running `./deploy/99_cleanup.sh` tears down all resources with one command to ensure zero ongoing costs.*
   > 
   > *Thank you, and I am now happy to answer any questions."*

---

## Common Viva / Examiner Questions & Answers

**Q1: Why did you use Cloud Run instead of Compute Engine VMs?**  
*Answer:* Cloud Run is serverless and scales to zero instances when traffic ceases, meaning zero idle compute cost. It also handles OS patching and SSL certificates automatically. We also documented the full VM alternative in our technical report.

**Q2: What is the purpose of V4 Signed URLs?**  
*Answer:* They allow clients to download private cloud objects directly from Google Cloud Storage without making the bucket public. The URL contains a cryptographic HMAC-SHA256 signature generated by our service account that automatically expires after 10 minutes.

**Q3: Why is `roles/iam.serviceAccountTokenCreator` granted to the service account on itself?**  
*Answer:* In Cloud Run, we don't store private key files in the container for security. To generate V4 signed URLs, the Python client calls Google's IAM `signBlob` API to sign the URL using the runtime service account identity.

**Q4: How does the application prevent cross-bucket tampering?**  
*Answer:* The IAM role `roles/storage.objectAdmin` is bound exclusively at the individual bucket level, not project-wide. If the application attempted to access any other bucket in the GCP project, Google Cloud would return an `AccessDeniedException`.
