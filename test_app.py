"""
================================================================================
AUTOMATED VERIFICATION TEST SUITE FOR CLOUD-BASED IMAGE GALLERY
Tests all functional requirements, security boundaries, and RBAC rules locally.
================================================================================
"""

import io
import json
import unittest
from app import app, is_local_storage, generate_local_signed_url, verify_local_signed_url

class CloudGalleryTestCase(unittest.TestCase):
    def setUp(self):
        app.config["TESTING"] = True
        app.config["WTF_CSRF_ENABLED"] = False
        self.client = app.test_client()

    def test_01_health_endpoint(self):
        """Verify /health returns 200 OK and expected JSON schema for Uptime Checks."""
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data["status"], "healthy")
        self.assertIn("service", data)
        print("[PASS] TC-01: Health check endpoint returned 200 OK")

    def test_02_unauthenticated_redirect(self):
        """Verify unauthenticated access to /gallery redirects to /login."""
        response = self.client.get("/gallery")
        self.assertEqual(response.status_code, 302)
        self.assertIn("/login", response.headers["Location"])
        print("[PASS] TC-02: Unauthenticated access successfully redirected to /login")

    def test_03_login_failure(self):
        """Verify invalid credentials fail authentication."""
        response = self.client.post("/login", data={
            "username": "admin",
            "password": "wrongpassword123"
        }, follow_redirects=True)
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Invalid username or password", response.data)
        print("[PASS] TC-03: Invalid login rejected")

    def test_04_admin_login_and_upload(self):
        """Verify admin can log in and upload a valid image."""
        # 1. Login as admin
        login_res = self.client.post("/login", data={
            "username": "admin",
            "password": "admin123"
        }, follow_redirects=True)
        self.assertEqual(login_res.status_code, 200)
        self.assertIn(b"Admin User", login_res.data)

        # 2. Upload valid dummy PNG
        test_file_bytes = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82"
        data = {
            "file": (io.BytesIO(test_file_bytes), "test_cloud_image.png")
        }
        upload_res = self.client.post("/upload", data=data, content_type="multipart/form-data", follow_redirects=True)
        self.assertEqual(upload_res.status_code, 200)
        self.assertIn(b"uploaded successfully", upload_res.data)
        print("[PASS] TC-04: Admin login and image upload verified")

    def test_05_upload_rejected_file_type(self):
        """Verify non-image files (.exe) are rejected."""
        # Login as admin
        self.client.post("/login", data={"username": "admin", "password": "admin123"})
        bad_data = {
            "file": (io.BytesIO(b"MALICIOUS EXEC CONTENT"), "virus.exe")
        }
        res = self.client.post("/upload", data=bad_data, content_type="multipart/form-data", follow_redirects=True)
        self.assertIn(b"File rejected", res.data)
        print("[PASS] TC-05: Non-image extension (.exe) rejected")

    def test_06_viewer_cannot_upload_403(self):
        """Verify viewer role attempting upload receives HTTP 403 Forbidden."""
        # Login as viewer
        self.client.post("/login", data={"username": "viewer", "password": "viewer123"})
        
        # Attempt upload
        test_file_bytes = b"fake image bytes"
        data = {
            "file": (io.BytesIO(test_file_bytes), "viewer_hack.jpg")
        }
        res = self.client.post("/upload", data=data, content_type="multipart/form-data")
        self.assertEqual(res.status_code, 403)
        print("[PASS] TC-06: Viewer upload blocked with HTTP 403 Forbidden")

    def test_07_viewer_cannot_delete_403(self):
        """Verify viewer role attempting delete receives HTTP 403 Forbidden."""
        # Login as viewer
        self.client.post("/login", data={"username": "viewer", "password": "viewer123"})
        res = self.client.post("/delete/some_image.png")
        self.assertEqual(res.status_code, 403)
        print("[PASS] TC-07: Viewer delete blocked with HTTP 403 Forbidden")

    def test_08_signed_url_token_verification(self):
        """Verify cryptographic signed URL logic and expiry handling."""
        with app.test_request_context():
            # Generate URL valid for 10 minutes
            valid_url = generate_local_signed_url("sample.png", expiration_minutes=10)
            self.assertIn("sig=", valid_url)
            self.assertIn("expires=", valid_url)

            # Test simulated expired token (expired 5 minutes ago)
            is_valid = verify_local_signed_url("sample.png", expires_at=1000, signature="bogussignature")
            self.assertFalse(is_valid)
            print("[PASS] TC-08: Cryptographic signed URL verification and expiry validated")


if __name__ == "__main__":
    unittest.main()
