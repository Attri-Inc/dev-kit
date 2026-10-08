# Fixture: vulnerable-tf

**Expected to be caught by:** `_terraform.yml` (Checkov + Trivy IaC).

Plants: public-read S3 ACL, wide-open SG (0.0.0.0/0:0-65535), publicly-accessible RDS with plaintext password and disabled encryption.
