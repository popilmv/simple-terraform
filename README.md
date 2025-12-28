# Simple Terraform App (EC2 + Docker + Stub / ECR mode)

This project provisions a **simple application infrastructure on AWS** using **Terraform**.
It deploys an EC2 instance running Docker and Docker Compose, with Nginx as a reverse proxy.

The application supports **two modes**:
- **Stub mode** – used when no application images exist in ECR (default)
- **ECR mode** – automatically enabled when `latest` images are available in ECR

---

## Architecture

- **VPC** with public subnet
- **EC2 (Amazon Linux 2023)**
- **Security Group** (HTTP :80)
- **ECR repositories** (frontend, backend)
- **IAM role** for:
  - ECR read-only access
  - AWS Systems Manager (SSM)
- **Docker + Docker Compose** on EC2
- **Nginx** reverse proxy

---

## Terraform State

Terraform state is stored remotely:

- **S3 bucket**: `simple-app-tfstate-eu-central-1`
- **State file key**: `simple-app/terraform.tfstate`
- **DynamoDB table**: `simple-app-tf-locks` (state locking)
- **Encryption**: enabled

