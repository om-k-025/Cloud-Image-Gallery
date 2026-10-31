"""
================================================================================
CLOUD-BASED IMAGE GALLERY (GCP + Flask + Cloud Storage + Cloud Run)
================================================================================
Course / Project: College Cloud Computing Mini-Project
Architecture:
  Client (Browser) -> HTTPS -> Cloud Run (Containerized Flask App)
                            -> Google Cloud Storage (Private Bucket, V4 Signed URLs)
Security & IAM:
  - Role-Based Access Control (Admin vs. Viewer)
  - Uniform Bucket-Level Access ON, Public Access Prevention ENFORCED
  - Principle of Least Privilege: dedicated 'gallery-app-sa' service account
  - Short-lived V4 Signed URLs (10-minute expiry) for image delivery
Logging:
  - Structured stdout logs automatically ingested by Google Cloud Logging
================================================================================
"""

import os
import sys
import json
import time
import hmac
import hashlib
import datetime
import logging
from functools import wraps
from typing import Dict, List, Optional, Tuple

from flask import (
    Flask,
    render_template,
    request,
    redirect,
    url_for,
    session,
    flash,
    abort,
    jsonify,
    send_from_directory,
)
from werkzeug.utils import secure_filename
from werkzeug.security import generate_password_hash, check_password_hash
from dotenv import load_dotenv

# Load local environment variables from .env if present
load_dotenv()

# Initialize Flask application
app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "dev-cloud-gallery-secret-key-change-me-in-prod")

# Configuration Constants
ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg", "gif", "webp"}
MAX_FILE_SIZE_MB = 5
app.config["MAX_CONTENT_LENGTH"] = MAX_FILE_SIZE_MB * 1024 * 1024  # 5 MB upload limit

# GCP Storage Configuration
GCP_PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "")
GCS_BUCKET_NAME = os.environ.get("GCS_BUCKET_NAME", "")
LOCAL_STORAGE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "local_storage")
SIGNED_URL_EXPIRATION_MINUTES = 10

# ------------------------------------------------------------------------------
# Structured Cloud Logging Setup
# ------------------------------------------------------------------------------
# Google Cloud Logging automatically ingests and indexes stdout/stderr as structured
# JSON logs when the JSON payload contains standard fields like "severity" and "message".
class CloudJsonFormatter(logging.Formatter):
    """Formats log records as single-line JSON objects for Google Cloud Logging."""
    def format(self, record):
        log_entry = {
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "severity": record.levelname,
            "message": record.getMessage(),
            "component": "image-gallery-app",
        }
        # Include custom metadata if attached to the log record
        if hasattr(record, "extra_fields"):
            log_entry.update(record.extra_fields)
        return json.dumps(log_entry)

handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(CloudJsonFormatter())
logger = logging.getLogger("cloud_gallery")
logger.setLevel(logging.INFO)
logger.handlers = [handler]
logger.propagate = False


def log_event(severity: str, event_type: str, message: str, **kwargs):
    """Helper to emit structured audit and operational logs to stdout."""
    extra = {"event": event_type, **kwargs}
    record = logger.makeRecord(
        logger.name,
        getattr(logging, severity.upper(), logging.INFO),
        fn="",
        lno=0,
        msg=f"[{event_type}] {message}",
        args=(),
        exc_info=None,
        extra={"extra_fields": extra},
    )
    logger.handle(record)


# ------------------------------------------------------------------------------
# Role-Based User Store (Hashed Passwords)
# ------------------------------------------------------------------------------
# Users are defined with roles: 'admin' (upload, view, delete) or 'viewer' (view only).
# Passwords can be overridden via environment variables for cloud security.
ADMIN_PASS = os.environ.get("ADMIN_PASSWORD", "admin123")
VIEWER_PASS = os.environ.get("VIEWER_PASSWORD", "viewer123")

USERS: Dict[str, Dict[str, str]] = {
    "admin": {
        "password_hash": generate_password_hash(ADMIN_PASS),
        "role": "admin",
        "display_name": "Admin User",
    },
    "viewer": {
        "password_hash": generate_password_hash(VIEWER_PASS),
        "role": "viewer",
        "display_name": "Auditor / Viewer",
    },
}

# ------------------------------------------------------------------------------
# Storage Backend Initialization (Google Cloud Storage vs. Local Mock Mode)
# ------------------------------------------------------------------------------
# In production on Cloud Run, google-cloud-storage interacts directly with the private
# GCS bucket using the attached IAM Service Account ('gallery-app-sa').
# For seamless local testing offline, a local storage mode is available.
gcs_client = None
gcs_bucket = None
is_local_storage = False

force_local = os.environ.get("LOCAL_STORAGE_MODE", "").lower() in ("true", "1", "yes")

if not force_local and GCS_BUCKET_NAME:
    try:
        from google.cloud import storage
        import google.auth
        # Authenticate using Google Cloud default credentials or service account key
        credentials, project = google.auth.default()
        gcs_client = storage.Client(project=GCP_PROJECT_ID or project, credentials=credentials)
        gcs_bucket = gcs_client.bucket(GCS_BUCKET_NAME)
        log_event("INFO", "STORAGE_INIT", f"Connected to Google Cloud Storage bucket: {GCS_BUCKET_NAME}")
    except Exception as e:
        log_event("WARNING", "STORAGE_INIT_FALLBACK", f"Could not initialize GCS ({e}). Falling back to local offline storage.")
        is_local_storage = True
else:
    is_local_storage = True

if is_local_storage:
    os.makedirs(LOCAL_STORAGE_DIR, exist_ok=True)
    log_event("INFO", "STORAGE_INIT", f"Operating in LOCAL_STORAGE_MODE using folder: {LOCAL_STORAGE_DIR}")


# ------------------------------------------------------------------------------
# Signed URL Generation & Validation Helpers
# ------------------------------------------------------------------------------
def generate_gcs_signed_url(blob_name: str, expiration_minutes: int = SIGNED_URL_EXPIRATION_MINUTES) -> str:
    """
    Generates a secure, short-lived V4 signed URL for a private GCS object.
    
    Cloud Architecture Note:
    - The bucket has Uniform Bucket-Level Access ON and Public Access Prevention ENFORCED.
    - Direct access (https://storage.googleapis.com/bucket/object) returns HTTP 403 Forbidden.
    - Only signed URLs with temporary cryptographic signatures allow authorized read access.
    """
    blob = gcs_bucket.blob(blob_name)
    expiration = datetime.timedelta(minutes=expiration_minutes)

    # Attempt standard V4 signed URL generation
    try:
        url = blob.generate_signed_url(
            version="v4",
            expiration=expiration,
            method="GET",
        )
        return url
    except Exception as e:
        # On Cloud Run, standard google.auth default credentials might not have a local private key.
        # We can use IAM signBlob service with the compute service account token creator role.
        try:
            import google.auth
            from google.auth.transport import requests as auth_requests
            credentials, _ = google.auth.default()
            auth_req = auth_requests.Request()
            credentials.refresh(auth_req)
            
            # Use service_account_email and access_token for signing via IAM
            service_account_email = getattr(credentials, "service_account_email", None)
            if service_account_email:
                url = blob.generate_signed_url(
                    version="v4",
                    expiration=expiration,
                    method="GET",
                    service_account_email=service_account_email,
                    access_token=credentials.token,
                )
                return url
        except Exception as inner_e:
            log_event("ERROR", "SIGNED_URL_FAILED", f"IAM signing fallback failed: {inner_e}")
        raise e


def generate_local_signed_url(filename: str, expiration_minutes: int = SIGNED_URL_EXPIRATION_MINUTES) -> str:
    """
    Simulates a short-lived signed URL for local offline testing using HMAC-SHA256 tokens.
    Guarantees that expired links fail with HTTP 403 just like GCS signed URLs.
    """
    expires_at = int(time.time()) + (expiration_minutes * 60)
    signature = hmac.new(
        app.secret_key.encode("utf-8"),
        f"{filename}:{expires_at}".encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    return url_for("serve_local_signed_image", filename=filename, expires=expires_at, sig=signature)


def verify_local_signed_url(filename: str, expires_at: int, signature: str) -> bool:
    """Verifies HMAC signature and expiration timestamp for simulated signed URLs."""
    if time.time() > expires_at:
        return False  # Expired
    expected = hmac.new(
        app.secret_key.encode("utf-8"),
        f"{filename}:{expires_at}".encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(expected, signature)


def allowed_file(filename: str) -> bool:
    """Validates that the file has an approved image extension."""
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS


# ------------------------------------------------------------------------------
# Authentication & Authorization Decorators
# ------------------------------------------------------------------------------
def login_required(f):
    """Enforces that the user has an active session; redirects to login otherwise."""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if "user" not in session:
            flash("Please log in to access the gallery.", "warning")
            return redirect(url_for("login", next=request.path))
        return f(*args, **kwargs)
    return decorated_function


def role_required(required_role: str):
    """
    Enforces Role-Based Access Control (RBAC).
    If a user with an insufficient role attempts an action, logs a security event
    and immediately returns HTTP 403 Forbidden.
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            if "user" not in session:
                return redirect(url_for("login"))
            user_role = session.get("role", "viewer")
            if user_role != required_role:
                log_event(
                    "WARNING",
                    "ACCESS_DENIED_403",
                    f"User '{session.get('user')}' with role '{user_role}' denied access to admin endpoint '{request.path}'",
                    user=session.get("user"),
                    user_role=user_role,
                    required_role=required_role,
                    path=request.path,
                    client_ip=request.remote_addr,
                )
                # Functional requirement: return explicit 403 for unauthorized viewer action
                abort(403, description=f"Access Denied: Role '{required_role}' required. Current role is '{user_role}'.")
            return f(*args, **kwargs)
        return decorated_function
    return decorator


# ------------------------------------------------------------------------------
# Application Routes
# ------------------------------------------------------------------------------
@app.route("/")
def index():
    """Root route: redirects authenticated users to gallery, unauthenticated to login."""
    if "user" in session:
        return redirect(url_for("gallery"))
    return redirect(url_for("login"))


@app.route("/login", methods=["GET", "POST"])
def login():
    """User authentication route handling credential verification and audit logging."""
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")

        user_record = USERS.get(username)
        if user_record and check_password_hash(user_record["password_hash"], password):
            session["user"] = username
            session["role"] = user_record["role"]
            session["display_name"] = user_record["display_name"]

            log_event(
                "INFO",
                "LOGIN_SUCCESS",
                f"User '{username}' logged in successfully with role '{user_record['role']}'",
                user=username,
                role=user_record["role"],
                client_ip=request.remote_addr,
            )
            flash(f"Welcome back, {user_record['display_name']}!", "success")
            next_url = request.args.get("next") or url_for("gallery")
            return redirect(next_url)
        else:
            log_event(
                "WARNING",
                "LOGIN_FAILURE",
                f"Failed login attempt for username '{username}'",
                attempted_user=username,
                client_ip=request.remote_addr,
            )
            flash("Invalid username or password. Please try again.", "danger")

    return render_template("login.html")


@app.route("/logout")
def logout():
    """Logs out user, clears session cookies, and emits audit log."""
    username = session.get("user", "anonymous")
    log_event("INFO", "LOGOUT", f"User '{username}' logged out", user=username, client_ip=request.remote_addr)
    session.clear()
    flash("You have been logged out successfully.", "info")
    return redirect(url_for("login"))


@app.route("/gallery")
@login_required
def gallery():
    """
    Displays image gallery with short-lived signed URLs for thumbnails and full views.
    Demonstrates least-privilege view permissions for both 'admin' and 'viewer'.
    """
    images = []
    start_time = time.time()

    if is_local_storage:
        # Read from local storage folder
        for filename in sorted(os.listdir(LOCAL_STORAGE_DIR), reverse=True):
            if allowed_file(filename):
                file_path = os.path.join(LOCAL_STORAGE_DIR, filename)
                size_kb = round(os.path.getsize(file_path) / 1024, 1)
                signed_url = generate_local_signed_url(filename)
                images.append({
                    "name": filename,
                    "url": signed_url,
                    "size_kb": size_kb,
                    "uploaded_at": datetime.datetime.fromtimestamp(os.path.getmtime(file_path)).strftime("%Y-%m-%d %H:%M"),
                })
    else:
        # Read objects from Google Cloud Storage private bucket
        try:
            blobs = gcs_client.list_blobs(gcs_bucket)
            for blob in blobs:
                if allowed_file(blob.name):
                    signed_url = generate_gcs_signed_url(blob.name)
                    images.append({
                        "name": blob.name,
                        "url": signed_url,
                        "size_kb": round((blob.size or 0) / 1024, 1),
                        "uploaded_at": blob.time_created.strftime("%Y-%m-%d %H:%M") if blob.time_created else "N/A",
                    })
        except Exception as e:
            log_event("ERROR", "STORAGE_LIST_ERROR", f"Failed to list GCS bucket objects: {e}")
            flash(f"Error fetching images from cloud storage: {e}", "danger")

    elapsed_ms = round((time.time() - start_time) * 1000, 2)
    log_event(
        "INFO",
        "GALLERY_ACCESSED",
        f"Gallery loaded {len(images)} images in {elapsed_ms}ms for user '{session.get('user')}'",
        user=session.get("user"),
        role=session.get("role"),
        image_count=len(images),
        load_time_ms=elapsed_ms,
    )

    return render_template(
        "gallery.html",
        images=images,
        user=session.get("user"),
        role=session.get("role"),
        display_name=session.get("display_name"),
        storage_mode="Local Storage (Offline Mock)" if is_local_storage else f"GCS Bucket ({GCS_BUCKET_NAME})",
        signed_expiry=SIGNED_URL_EXPIRATION_MINUTES,
    )


@app.route("/upload", methods=["GET", "POST"])
@login_required
@role_required("admin")
def upload():
    """
    Image upload endpoint restricted to 'admin' role.
    Performs server-side validation on file extension, file size, and sanitized filename.
    """
    if request.method == "POST":
        if "file" not in request.files:
            flash("No file part in the upload request.", "warning")
            return redirect(request.url)

        file = request.files["file"]
        if file.filename == "":
            flash("No file was selected for upload.", "warning")
            return redirect(request.url)

        if not allowed_file(file.filename):
            log_event(
                "WARNING",
                "UPLOAD_REJECTED",
                f"File '{file.filename}' rejected: extension not allowed",
                user=session.get("user"),
                filename=file.filename,
            )
            flash("File rejected: Only JPG, PNG, GIF, and WEBP images are allowed.", "danger")
            return redirect(request.url)

        # Sanitize filename and prepend timestamp to prevent collisions
        safe_base = secure_filename(file.filename)
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        unique_filename = f"{timestamp}_{safe_base}"

        # Read content and enforce size check
        file_bytes = file.read()
        file_size_bytes = len(file_bytes)

        if file_size_bytes > app.config["MAX_CONTENT_LENGTH"]:
            flash(f"File too large ({round(file_size_bytes/(1024*1024), 2)} MB). Max limit is {MAX_FILE_SIZE_MB} MB.", "danger")
            return redirect(request.url)

        # Determine MIME type
        content_type = file.content_type or "application/octet-stream"

        if is_local_storage:
            target_path = os.path.join(LOCAL_STORAGE_DIR, unique_filename)
            with open(target_path, "wb") as f_out:
                f_out.write(file_bytes)
        else:
            try:
                blob = gcs_bucket.blob(unique_filename)
                blob.upload_from_string(file_bytes, content_type=content_type)
            except Exception as e:
                log_event("ERROR", "UPLOAD_FAILED", f"GCS upload failed: {e}", filename=unique_filename)
                flash(f"Cloud Storage upload failed: {e}", "danger")
                return redirect(request.url)

        log_event(
            "INFO",
            "IMAGE_UPLOAD",
            f"Image '{unique_filename}' ({file_size_bytes} bytes) uploaded by '{session.get('user')}'",
            user=session.get("user"),
            filename=unique_filename,
            size_bytes=file_size_bytes,
            content_type=content_type,
        )
        flash(f"Image '{safe_base}' uploaded successfully!", "success")
        return redirect(url_for("gallery"))

    return render_template(
        "upload.html",
        user=session.get("user"),
        role=session.get("role"),
        max_size_mb=MAX_FILE_SIZE_MB,
        allowed_extensions=", ".join(sorted(ALLOWED_EXTENSIONS)).upper(),
    )


@app.route("/delete/<path:filename>", methods=["POST"])
@login_required
@role_required("admin")
def delete(filename: str):
    """
    Image deletion endpoint restricted to 'admin' role.
    Removes object from storage and records audit log.
    """
    safe_name = secure_filename(filename)

    if is_local_storage:
        target_path = os.path.join(LOCAL_STORAGE_DIR, safe_name)
        if os.path.exists(target_path):
            os.remove(target_path)
            log_event("INFO", "IMAGE_DELETE", f"Image '{safe_name}' deleted by '{session.get('user')}'", user=session.get("user"), filename=safe_name)
            flash(f"Image '{safe_name}' was deleted.", "success")
        else:
            flash(f"Image '{safe_name}' not found.", "warning")
    else:
        try:
            blob = gcs_bucket.blob(safe_name)
            if blob.exists():
                blob.delete()
                log_event("INFO", "IMAGE_DELETE", f"GCS object '{safe_name}' deleted by '{session.get('user')}'", user=session.get("user"), filename=safe_name)
                flash(f"Image '{safe_name}' was deleted from cloud storage.", "success")
            else:
                flash(f"Object '{safe_name}' was not found in bucket.", "warning")
        except Exception as e:
            log_event("ERROR", "DELETE_FAILED", f"Failed to delete '{safe_name}': {e}", filename=safe_name)
            flash(f"Failed to delete image: {e}", "danger")

    return redirect(url_for("gallery"))


@app.route("/local-media/<path:filename>")
def serve_local_signed_image(filename: str):
    """
    Serves images in local mock mode ONLY if the signed URL token is valid and unexpired.
    Demonstrates short-lived signed URL expiration behavior even without GCP access.
    """
    if not is_local_storage:
        abort(404)

    expires = request.args.get("expires", type=int)
    sig = request.args.get("sig", "")

    if not expires or not sig or not verify_local_signed_url(filename, expires, sig):
        log_event(
            "WARNING",
            "SIGNED_URL_REJECTED",
            f"Access to '{filename}' rejected: invalid or expired signed URL token",
            filename=filename,
            client_ip=request.remote_addr,
        )
        abort(403, description="Forbidden: Signed URL has expired or has an invalid signature.")

    return send_from_directory(LOCAL_STORAGE_DIR, secure_filename(filename))


@app.route("/health")
def health():
    """
    Health check endpoint for Cloud Run and Cloud Monitoring Uptime Checks.
    Returns 200 OK with operational status.
    """
    return jsonify({
        "status": "healthy",
        "service": "cloud-image-gallery",
        "storage_backend": "local" if is_local_storage else "gcs",
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }), 200


# ------------------------------------------------------------------------------
# Error Handlers
# ------------------------------------------------------------------------------
@app.errorhandler(403)
def forbidden_error(error):
    """Handles HTTP 403 Forbidden with a clear security alert page."""
    return render_template(
        "login.html",
        error_title="403 - Forbidden / Access Denied",
        error_message=str(error.description) if hasattr(error, "description") else "You do not have permission to perform this action.",
    ), 403


@app.errorhandler(404)
def not_found_error(error):
    """Handles HTTP 404 Not Found."""
    return render_template(
        "login.html",
        error_title="404 - Page Not Found",
        error_message="The requested page or image could not be found.",
    ), 404


@app.errorhandler(413)
def request_entity_too_large(error):
    """Handles files exceeding MAX_CONTENT_LENGTH."""
    flash(f"File upload rejected: Size exceeds the maximum allowed limit of {MAX_FILE_SIZE_MB} MB.", "danger")
    return redirect(url_for("upload"))


# ------------------------------------------------------------------------------
# Entrypoint for Local Execution
# ------------------------------------------------------------------------------
if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    print(f"""
    ===============================================================
    CLOUD-BASED IMAGE GALLERY (Flask + GCP Storage)
    Running at: http://localhost:{port}
    Role Accounts:
      - Admin:  username 'admin',  password '{ADMIN_PASS}'
      - Viewer: username 'viewer', password '{VIEWER_PASS}'
    Storage Mode: {'LOCAL OFFLINE MOCK' if is_local_storage else f'GOOGLE CLOUD STORAGE ({GCS_BUCKET_NAME})'}
    ===============================================================
    """)
    app.run(host="0.0.0.0", port=port, debug=True)
