# Certbot Route53 GitHub Action

This GitHub Action allows you to add or renew Let's Encrypt certificates using Certbot and AWS Route53. The generated certificates are securely stored in an AWS S3 bucket.

## Features
- Generate and renew SSL/TTLS certificates using Certbot.
- Supports wildcard certificates via DNS-01 challenges with AWS Route53.
- Securely stores certificates in an S3 bucket.
- Optional password protection for the archived certificate files.
- Supports testing mode using Let's Encrypt staging servers.
- **Detects whether a certificate was renewed or not** and outputs the status.

---

## Inputs

| Name               | Description                                                                                           | Required | Default        |
|--------------------|-------------------------------------------------------------------------------------------------------|----------|----------------|
| `aws-access-key-id`| AWS Access Key ID for Route53 and S3 operations.                                                      | ✅        | -              |
| `aws-access-key`   | AWS Secret Access Key for Route53 and S3 operations.                                                 | ✅        | -              |
| `aws-region`       | AWS Region where Route53 and S3 are located.                                                         | ✅        | -              |
| `bucket`           | AWS S3 bucket where the certificate is stored.                                                       | ✅        | -              |
| `tar-password`     | Password to protect the uploaded tar file (optional).                                                | ❌        | `''`           |
| `email`            | Email for Let's Encrypt account (used for renewal notifications).                                    | ✅        | -              |
| `domains`          | Comma-separated list of domains for which certificates will be generated.                            | ✅        | -              |
| `file-path`        | Relative path for the certificate file (no leading `/`); `.tar.gz` is automatically appended.         | ✅        | -              |
| `generate-fullcert`| Generate a full certificate chain + private key (e.g., for haproxy).                                  | ❌        | `false`        |
| `test-cert`        | Use Let's Encrypt staging server for testing (set to `true` for testing purposes).                   | ❌        | `false`        |
| `dry-run`          | Simulate the process without generating certificates (set to `true` for configuration testing).       | ❌        | `false`        |

---

## Outputs

| Name               | Description                                                   |
|--------------------|---------------------------------------------------------------|
| `certificate-name` | The name of the generated or renewed certificate.             |
| `certificate-path` | The path to the generated or renewed certificate file.        |
| `certificate-s3-path` | The S3 path where the generated or renewed certificate file is stored.     |
| `renewal-status`   | Indicates whether the certificate was renewed (`renewed`) or skipped because it was not yet due for renewal (`not-renewed`). |

---

## Usage

### Basic Example
```yaml
jobs:
  generate-certificates:
    runs-on: ubuntu-latest
    steps:
      - name: Generate/Renew Certificates
        uses: hhgyu/certbot-route53@v1
        id: certbot
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: "us-east-1"
          bucket: "my-s3-bucket"
          email: "user@example.com"
          domains: "example.com,*.example.com"
          file-path: "certs/example"
          test-cert: "true"
          generate-fullcert: "true"

      - name: Check Renewal Status
        run: echo "Renewal status: ${{ steps.certbot.outputs.renewal-status }}"