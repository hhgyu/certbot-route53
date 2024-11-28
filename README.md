# Certbot Route53 GitHub Action

This GitHub Action allows you to add or renew Let's Encrypt certificates using Certbot and AWS Route53. The generated certificates are securely stored in an AWS S3 bucket.

## Features
- Generate and renew SSL/TLS certificates using Certbot.
- Supports wildcard certificates via DNS-01 challenges with AWS Route53.
- Securely stores certificates in an S3 bucket.
- Optional password protection for the archived certificate files.
- Supports testing mode using Let's Encrypt staging servers.

---

## Inputs

| Name               | Description                                                                                           | Required | Default        |
|--------------------|-------------------------------------------------------------------------------------------------------|----------|----------------|
| `aws-access-key-id`| AWS Access Key ID for Route53 and S3 operations.                                                      | ✅        | -              |
| `aws-access-key`   | AWS Secret Access Key for Route53 and S3 operations.                                                 | ✅        | -              |
| `aws-region`       | AWS Region where Route53 and S3 are located.                                                         | ✅        | -              |
| `bucket`           | AWS S3 bucket where the certificate is stored.                                                       | ✅        | -              |
| `bucket-path`      | Path within the bucket to store the certificate.                                                     | ❌        | -              |
| `tar-password`     | Password to protect the uploaded tar file (optional).                                                | ❌        | `''`           |
| `email`            | Email for Let's Encrypt account (used for renewal notifications).                                    | ✅        | -              |
| `domains`          | Comma-separated list of domains for which certificates will be generated.                            | ✅        | -              |
| `file-path`        | Relative path for the certificate file (no leading `/`); `.tar.gz` is automatically appended.         | ✅        | -              |
| `test-cert`        | Use Let's Encrypt staging server for testing (set to `true` for testing purposes).                   | ❌        | `false`        |
| `dry-run`          | Simulate the process without generating certificates (set to `true` for configuration testing).       | ❌        | `false`        |

---

## Outputs

| Name               | Description                                                   |
|--------------------|---------------------------------------------------------------|
| `certificate-name` | The name of the generated or renewed certificate.             |
| `certificate-path` | The path to the generated or renewed certificate file.        |

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
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: "us-east-1"
          bucket: "my-s3-bucket"
          bucket-path: "certificates"
          email: "user@example.com"
          domains: "example.com,*.example.com"
          file-path: "certs/example"
          test-cert: "true"
